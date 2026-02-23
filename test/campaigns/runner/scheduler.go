package main

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"
)

// Scheduler evaluates campaign triggers and orchestrates execution.
type Scheduler struct {
	registry   map[string]*Campaign
	dispatcher *Dispatcher
	collector  *Collector
}

// NewScheduler creates a Scheduler with the given campaign registry.
func NewScheduler(registry map[string]*Campaign, dispatcher *Dispatcher, collector *Collector) *Scheduler {
	return &Scheduler{
		registry:   registry,
		dispatcher: dispatcher,
		collector:  collector,
	}
}

// RunDue evaluates all campaigns and runs those whose triggers are satisfied.
func (s *Scheduler) RunDue(ctx context.Context) {
	now := time.Now().UTC()
	for id, campaign := range s.registry {
		if !s.isDue(campaign, now) {
			continue
		}
		log.Printf("campaign %s: trigger satisfied, dispatching", id)
		timeout := parseDuration(campaign.Guardrails.MaxDuration)
		runCtx, cancel := context.WithTimeout(ctx, timeout)
		if err := s.RunCampaign(runCtx, campaign); err != nil {
			log.Printf("campaign %s: failed: %v", id, err)
		}
		cancel()
	}
}

// RunCampaign executes a single campaign end-to-end.
func (s *Scheduler) RunCampaign(ctx context.Context, campaign *Campaign) error {
	runID := fmt.Sprintf("%s-%d", campaign.ID, time.Now().Unix())
	log.Printf("campaign %s: starting run %s (agent=%s, timeout=%s)",
		campaign.ID, runID, campaign.Agent, campaign.Guardrails.MaxDuration)

	// Check global kill switch.
	if killed, err := s.collector.CheckKillSwitch(ctx); err != nil {
		log.Printf("campaign %s: kill switch check error: %v (continuing)", campaign.ID, err)
	} else if killed {
		log.Printf("campaign %s: global kill switch active, skipping", campaign.ID)
		return fmt.Errorf("global kill switch active")
	}

	result := &CampaignResult{
		CampaignID: campaign.ID,
		RunID:      runID,
		Agent:      campaign.Agent,
		StartedAt:  time.Now().UTC().Format(time.RFC3339),
	}

	// Dispatch to agent via rj-gateway MCP.
	dispatchResult, err := s.dispatcher.Dispatch(ctx, campaign, runID)
	if err != nil {
		result.Status = "error"
		result.Error = err.Error()
		result.FinishedAt = time.Now().UTC().Format(time.RFC3339)
		s.storeResult(ctx, campaign, result)
		return err
	}

	result.ToolCalls = dispatchResult.ToolCalls
	result.KPIs = dispatchResult.KPIs

	if ctx.Err() != nil {
		result.Status = "timeout"
		result.Error = ctx.Err().Error()
	} else if dispatchResult.Error != "" {
		result.Status = "failure"
		result.Error = dispatchResult.Error
	} else {
		result.Status = "success"
	}

	result.FinishedAt = time.Now().UTC().Format(time.RFC3339)

	log.Printf("campaign %s: run %s completed (status=%s, tools=%d)",
		campaign.ID, runID, result.Status, result.ToolCalls)

	s.storeResult(ctx, campaign, result)
	return nil
}

// storeResult persists the campaign result via the collector.
func (s *Scheduler) storeResult(ctx context.Context, campaign *Campaign, result *CampaignResult) {
	if err := s.collector.StoreResult(ctx, campaign, result); err != nil {
		log.Printf("campaign %s: failed to store result: %v", campaign.ID, err)
	}
}

// isDue checks if a campaign's trigger is satisfied at the given time.
func (s *Scheduler) isDue(campaign *Campaign, now time.Time) bool {
	trigger := campaign.Trigger

	// Manual-only campaigns never auto-trigger.
	if trigger.Schedule == "" && trigger.Event == "manual" {
		return false
	}

	// Event-triggered campaigns (push, PR) are dispatched externally.
	if trigger.Event == "push" || trigger.Event == "pull_request" {
		return false
	}

	// Evaluate cron schedule.
	if trigger.Schedule != "" {
		return cronMatches(trigger.Schedule, now)
	}

	return false
}

// cronMatches evaluates a simple 5-field cron expression against a time.
// Format: minute hour day-of-month month day-of-week
// Supports: numbers, * (any), and ranges are not implemented (keep it simple).
func cronMatches(expr string, t time.Time) bool {
	fields := strings.Fields(expr)
	if len(fields) != 5 {
		return false
	}

	checks := []struct {
		field string
		value int
	}{
		{fields[0], t.Minute()},
		{fields[1], t.Hour()},
		{fields[2], t.Day()},
		{fields[3], int(t.Month())},
		{fields[4], int(t.Weekday())}, // 0=Sunday
	}

	for _, c := range checks {
		if !cronFieldMatches(c.field, c.value) {
			return false
		}
	}
	return true
}

// cronFieldMatches checks if a single cron field matches a value.
func cronFieldMatches(field string, value int) bool {
	if field == "*" {
		return true
	}
	n, err := strconv.Atoi(field)
	if err != nil {
		return false
	}
	return n == value
}
