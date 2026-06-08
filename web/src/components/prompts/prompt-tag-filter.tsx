"use client";

import { ChevronDown, ChevronUp } from "lucide-react";
import { Button, Tag } from "antd";
import { useMemo, useState } from "react";

import { cn } from "@/lib/utils";
import { ALL_PROMPTS_OPTION } from "@/services/api/prompts";

const COLLAPSED_TAG_LIMIT = 24;

type PromptTagFilterProps = {
    tags: string[];
    selectedTags: string[];
    onToggle: (tag: string) => void;
};

export function PromptTagFilter({ tags, selectedTags, onToggle }: PromptTagFilterProps) {
    const [expanded, setExpanded] = useState(false);
    const visibleTags = useMemo(() => {
        if (expanded || tags.length <= COLLAPSED_TAG_LIMIT) return tags;
        const selected = new Set(selectedTags);
        const primary = tags.slice(0, COLLAPSED_TAG_LIMIT);
        const extraSelected = tags.slice(COLLAPSED_TAG_LIMIT).filter((tag) => selected.has(tag));
        return [...primary, ...extraSelected];
    }, [expanded, selectedTags, tags]);
    const hiddenCount = Math.max(tags.length - visibleTags.length, 0);

    return (
        <div className="flex flex-wrap items-center gap-2">
            {visibleTags.map((tag, index) => {
                const active = tag === ALL_PROMPTS_OPTION ? selectedTags.length === 0 : selectedTags.includes(tag);
                return (
                    <Tag.CheckableTag key={`${tag}-${index}`} checked={active} className={cn("prompt-filter-tag", active && "is-active")} onChange={() => onToggle(tag)}>
                        {tag}
                    </Tag.CheckableTag>
                );
            })}
            {tags.length > COLLAPSED_TAG_LIMIT ? (
                <Button size="small" type="text" icon={expanded ? <ChevronUp className="size-3.5" /> : <ChevronDown className="size-3.5" />} onClick={() => setExpanded((value) => !value)}>
                    {expanded ? "收起" : `展开${hiddenCount ? ` ${hiddenCount}` : ""}`}
                </Button>
            ) : null}
        </div>
    );
}
