package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/basketikun/infinite-canvas/model"
	"github.com/google/uuid"
)

const aiProxyTaskTTL = 30 * time.Minute

type AIProxyTaskStatus string

const (
	AIProxyTaskQueued    AIProxyTaskStatus = "queued"
	AIProxyTaskRunning   AIProxyTaskStatus = "running"
	AIProxyTaskSucceeded AIProxyTaskStatus = "succeeded"
	AIProxyTaskFailed    AIProxyTaskStatus = "failed"
)

type AIProxyTaskCreateInput struct {
	User            model.AuthUser
	Endpoint        string
	Body            []byte
	ContentType     string
	ModelName       string
	ChannelID       string
	Count           int
	ClientID        string
	RequestBody     string
	UserDisplayName string
}

type AIProxyTaskSnapshot struct {
	ID          string            `json:"id"`
	Status      AIProxyTaskStatus `json:"status"`
	Endpoint    string            `json:"endpoint"`
	Model       string            `json:"model"`
	HTTPStatus  int               `json:"httpStatus,omitempty"`
	ContentType string            `json:"contentType,omitempty"`
	Error       string            `json:"error,omitempty"`
	ErrorDetail string            `json:"errorDetail,omitempty"`
	CreatedAt   string            `json:"createdAt"`
	UpdatedAt   string            `json:"updatedAt"`
	CompletedAt string            `json:"completedAt,omitempty"`
	ExpiresAt   string            `json:"expiresAt"`
}

type AIProxyTaskResult struct {
	Status      int
	ContentType string
	Body        []byte
}

type aiProxyTask struct {
	id          string
	userID      string
	clientKey   string
	status      AIProxyTaskStatus
	endpoint    string
	model       string
	httpStatus  int
	contentType string
	response    []byte
	errMessage  string
	errDetail   string
	createdAt   time.Time
	updatedAt   time.Time
	completedAt time.Time
	expiresAt   time.Time
}

var aiProxyTasks = struct {
	sync.Mutex
	items      map[string]*aiProxyTask
	clientKeys map[string]string
}{
	items:      map[string]*aiProxyTask{},
	clientKeys: map[string]string{},
}

func CreateAIProxyTask(input AIProxyTaskCreateInput) (AIProxyTaskSnapshot, error) {
	input.ModelName = strings.TrimSpace(input.ModelName)
	input.Endpoint = strings.TrimSpace(input.Endpoint)
	if input.Count < 1 {
		input.Count = 1
	}
	if input.ModelName == "" || input.Endpoint == "" {
		return AIProxyTaskSnapshot{}, safeMessageError{message: "AI 任务参数不完整"}
	}

	clientKey := aiProxyTaskClientKey(input.User.ID, input.ClientID)
	if snapshot, ok := existingAIProxyTask(clientKey); ok {
		return snapshot, nil
	}

	credits, err := ModelCost(input.ModelName)
	if err != nil {
		return AIProxyTaskSnapshot{}, err
	}
	credits *= input.Count
	channel, err := SelectModelChannelForModel(input.ModelName, input.ChannelID)
	if err != nil {
		return AIProxyTaskSnapshot{}, err
	}
	if err := ConsumeUserCredits(input.User.ID, input.ModelName, credits, input.Endpoint); err != nil {
		return AIProxyTaskSnapshot{}, err
	}

	now := time.Now()
	task := &aiProxyTask{
		id:        "ai-task-" + uuid.NewString(),
		userID:    input.User.ID,
		clientKey: clientKey,
		status:    AIProxyTaskQueued,
		endpoint:  input.Endpoint,
		model:     input.ModelName,
		createdAt: now,
		updatedAt: now,
		expiresAt: now.Add(aiProxyTaskTTL),
	}

	aiProxyTasks.Lock()
	cleanupAIProxyTasksLocked(now)
	if clientKey != "" {
		if existingID := aiProxyTasks.clientKeys[clientKey]; existingID != "" {
			if existing := aiProxyTasks.items[existingID]; existing != nil {
				snapshot := existing.snapshot()
				aiProxyTasks.Unlock()
				if err := RefundUserCredits(input.User.ID, input.ModelName, credits, input.Endpoint); err != nil {
					log.Printf("AI task duplicate refund failed: user=%s model=%s credits=%d err=%v", input.User.ID, input.ModelName, credits, err)
				}
				return snapshot, nil
			}
		}
		aiProxyTasks.clientKeys[clientKey] = task.id
	}
	aiProxyTasks.items[task.id] = task
	snapshot := task.snapshot()
	aiProxyTasks.Unlock()

	go runAIProxyTask(task.id, input, channel, credits)
	return snapshot, nil
}

func GetAIProxyTask(userID string, id string) (AIProxyTaskSnapshot, error) {
	aiProxyTasks.Lock()
	defer aiProxyTasks.Unlock()
	cleanupAIProxyTasksLocked(time.Now())
	task, ok := aiProxyTasks.items[id]
	if !ok || task.userID != userID {
		return AIProxyTaskSnapshot{}, safeMessageError{message: "AI 任务不存在"}
	}
	return task.snapshot(), nil
}

func ReadAIProxyTaskResult(userID string, id string) (AIProxyTaskResult, error) {
	aiProxyTasks.Lock()
	defer aiProxyTasks.Unlock()
	cleanupAIProxyTasksLocked(time.Now())
	task, ok := aiProxyTasks.items[id]
	if !ok || task.userID != userID {
		return AIProxyTaskResult{}, safeMessageError{message: "AI 任务不存在"}
	}
	if task.status != AIProxyTaskSucceeded {
		if task.errMessage != "" {
			return AIProxyTaskResult{}, safeMessageError{message: task.errMessage}
		}
		return AIProxyTaskResult{}, safeMessageError{message: "AI 任务尚未完成"}
	}
	return AIProxyTaskResult{Status: task.httpStatus, ContentType: task.contentType, Body: append([]byte(nil), task.response...)}, nil
}

func existingAIProxyTask(clientKey string) (AIProxyTaskSnapshot, bool) {
	if clientKey == "" {
		return AIProxyTaskSnapshot{}, false
	}
	aiProxyTasks.Lock()
	defer aiProxyTasks.Unlock()
	cleanupAIProxyTasksLocked(time.Now())
	id := aiProxyTasks.clientKeys[clientKey]
	task := aiProxyTasks.items[id]
	if task == nil {
		return AIProxyTaskSnapshot{}, false
	}
	return task.snapshot(), true
}

func runAIProxyTask(id string, input AIProxyTaskCreateInput, channel model.ModelChannel, credits int) {
	startedAt := time.Now()
	markAIProxyTaskRunning(id)

	request, err := http.NewRequest(http.MethodPost, BuildModelChannelURL(channel, input.Endpoint), bytes.NewReader(input.Body))
	if err != nil {
		failAIProxyTask(id, input, channel, credits, startedAt, 0, "AI 接口请求失败", err.Error())
		return
	}
	request.Header.Set("Authorization", "Bearer "+channel.APIKey)
	if input.ContentType != "" {
		request.Header.Set("Content-Type", input.ContentType)
	}

	response, err := HTTPClientForChannel(channel).Do(request)
	if err != nil {
		failAIProxyTask(id, input, channel, credits, startedAt, 0, "AI 接口请求失败", err.Error())
		return
	}
	defer response.Body.Close()

	if response.StatusCode >= http.StatusBadRequest {
		payload, _ := io.ReadAll(io.LimitReader(response.Body, 256*1024))
		message := readAIProxyTaskErrorMessage(payload, response.StatusCode)
		failAIProxyTask(id, input, channel, credits, startedAt, response.StatusCode, message, strings.TrimSpace(string(payload)))
		return
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		failAIProxyTask(id, input, channel, credits, startedAt, response.StatusCode, "AI 接口响应读取失败", err.Error())
		return
	}

	contentType := response.Header.Get("Content-Type")
	markAIProxyTaskSucceeded(id, response.StatusCode, contentType, body)
	SaveAICallLog(AICallLogInput{
		UserID:          input.User.ID,
		UserDisplayName: input.UserDisplayName,
		Endpoint:        input.Endpoint,
		Method:          http.MethodPost,
		Model:           input.ModelName,
		ChannelID:       channel.ID,
		ChannelName:     channel.Name,
		Status:          response.StatusCode,
		DurationMs:      time.Since(startedAt).Milliseconds(),
		Credits:         credits,
		RequestBody:     input.RequestBody,
		ResponseBody:    string(body),
	})
}

func failAIProxyTask(id string, input AIProxyTaskCreateInput, channel model.ModelChannel, credits int, startedAt time.Time, status int, message string, detail string) {
	log.Printf("AI async task failed: id=%s endpoint=%s model=%s status=%d err=%s detail=%s", id, input.Endpoint, input.ModelName, status, message, detail)
	if err := RefundUserCredits(input.User.ID, input.ModelName, credits, input.Endpoint); err != nil {
		log.Printf("AI async task refund failed: user=%s model=%s credits=%d err=%v", input.User.ID, input.ModelName, credits, err)
	}
	markAIProxyTaskFailed(id, status, message, detail)
	SaveAICallLog(AICallLogInput{
		UserID:          input.User.ID,
		UserDisplayName: input.UserDisplayName,
		Endpoint:        input.Endpoint,
		Method:          http.MethodPost,
		Model:           input.ModelName,
		ChannelID:       channel.ID,
		ChannelName:     channel.Name,
		Status:          status,
		DurationMs:      time.Since(startedAt).Milliseconds(),
		Credits:         credits,
		RequestBody:     input.RequestBody,
		ResponseBody:    detail,
		Error:           firstNonEmpty(message, detail, "AI 接口请求失败"),
	})
}

func markAIProxyTaskRunning(id string) {
	aiProxyTasks.Lock()
	defer aiProxyTasks.Unlock()
	if task := aiProxyTasks.items[id]; task != nil {
		task.status = AIProxyTaskRunning
		task.updatedAt = time.Now()
	}
}

func markAIProxyTaskSucceeded(id string, status int, contentType string, body []byte) {
	aiProxyTasks.Lock()
	defer aiProxyTasks.Unlock()
	if task := aiProxyTasks.items[id]; task != nil {
		now := time.Now()
		task.status = AIProxyTaskSucceeded
		task.httpStatus = status
		task.contentType = contentType
		task.response = append([]byte(nil), body...)
		task.errMessage = ""
		task.errDetail = ""
		task.updatedAt = now
		task.completedAt = now
		task.expiresAt = now.Add(aiProxyTaskTTL)
	}
}

func markAIProxyTaskFailed(id string, status int, message string, detail string) {
	aiProxyTasks.Lock()
	defer aiProxyTasks.Unlock()
	if task := aiProxyTasks.items[id]; task != nil {
		now := time.Now()
		task.status = AIProxyTaskFailed
		task.httpStatus = status
		task.errMessage = strings.TrimSpace(message)
		task.errDetail = strings.TrimSpace(detail)
		task.updatedAt = now
		task.completedAt = now
		task.expiresAt = now.Add(aiProxyTaskTTL)
	}
}

func cleanupAIProxyTasksLocked(now time.Time) {
	for id, task := range aiProxyTasks.items {
		if task.status == AIProxyTaskQueued || task.status == AIProxyTaskRunning || now.Before(task.expiresAt) {
			continue
		}
		delete(aiProxyTasks.items, id)
		if task.clientKey != "" {
			delete(aiProxyTasks.clientKeys, task.clientKey)
		}
	}
}

func (task *aiProxyTask) snapshot() AIProxyTaskSnapshot {
	snapshot := AIProxyTaskSnapshot{
		ID:          task.id,
		Status:      task.status,
		Endpoint:    task.endpoint,
		Model:       task.model,
		HTTPStatus:  task.httpStatus,
		ContentType: task.contentType,
		Error:       task.errMessage,
		ErrorDetail: task.errDetail,
		CreatedAt:   task.createdAt.Format(time.RFC3339),
		UpdatedAt:   task.updatedAt.Format(time.RFC3339),
		ExpiresAt:   task.expiresAt.Format(time.RFC3339),
	}
	if !task.completedAt.IsZero() {
		snapshot.CompletedAt = task.completedAt.Format(time.RFC3339)
	}
	return snapshot
}

func aiProxyTaskClientKey(userID string, clientID string) string {
	clientID = strings.TrimSpace(clientID)
	if userID == "" || clientID == "" {
		return ""
	}
	return userID + ":" + clientID
}

func readAIProxyTaskErrorMessage(body []byte, statusCode int) string {
	var payload struct {
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
		Msg     string `json:"msg"`
		Message string `json:"message"`
	}
	if len(body) > 0 && json.Unmarshal(body, &payload) == nil {
		if payload.Error != nil && strings.TrimSpace(payload.Error.Message) != "" {
			return payload.Error.Message
		}
		if strings.TrimSpace(payload.Msg) != "" {
			return payload.Msg
		}
		if strings.TrimSpace(payload.Message) != "" {
			return payload.Message
		}
	}
	if statusCode > 0 {
		return fmt.Sprintf("AI 接口请求失败：%d", statusCode)
	}
	return "AI 接口请求失败"
}
