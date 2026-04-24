package management

import (
	"testing"
	"time"

	coreauth "github.com/router-for-me/CLIProxyAPI/v6/sdk/cliproxy/auth"
)

func TestBuildQuotaSnapshotResponseAggregatesFreshness(t *testing.T) {
	now := time.Date(2026, 4, 21, 14, 0, 0, 0, time.UTC)
	lastRefresh := now.Add(-30 * time.Second)
	staleRefresh := now.Add(-3 * time.Minute)
	teamRemaining := 78
	weeklyRemaining := 64
	auths := []*coreauth.Auth{
		{
			ID:       "codex-alpha.json",
			FileName: "codex-alpha.json",
			Provider: "codex",
			Metadata: map[string]any{
				"email":                     "alpha@example.com",
				"codexkit_local_account_id": "local-alpha",
				"quota_snapshot": map[string]any{
					"plan_type":                   "team",
					"five_hour_remaining_percent": teamRemaining,
					"weekly_remaining_percent":    weeklyRemaining,
					"last_quota_refreshed_at":     lastRefresh.Format(time.RFC3339),
					"quota_refresh_status":        quotaRefreshStatusOK,
					"quota_source":                quotaSnapshotSourceService,
				},
			},
		},
		{
			ID:       "codex-beta.json",
			FileName: "codex-beta.json",
			Provider: "codex",
			Metadata: map[string]any{
				"email": "beta@example.com",
				"quota_snapshot": map[string]any{
					"plan_type":               "plus",
					"last_quota_refreshed_at": staleRefresh.Format(time.RFC3339),
					"quota_refresh_status":    quotaRefreshStatusOK,
					"quota_source":            quotaSnapshotSourceService,
				},
			},
		},
		{
			ID:       "claude-gamma.json",
			FileName: "claude-gamma.json",
			Provider: "claude",
			Metadata: map[string]any{"email": "gamma@example.com"},
		},
	}

	handler := &Handler{}
	snapshot := handler.buildQuotaSnapshotResponse(now, auths)

	if snapshot.RefreshStatus != quotaRefreshStatusStale {
		t.Fatalf("refresh status = %q, want %q", snapshot.RefreshStatus, quotaRefreshStatusStale)
	}
	if !snapshot.Stale {
		t.Fatalf("expected snapshot to be stale")
	}
	if len(snapshot.Accounts) != 3 {
		t.Fatalf("accounts count = %d, want 3", len(snapshot.Accounts))
	}
	if snapshot.Accounts[0].CodexkitLocalAccountID != "local-alpha" {
		t.Fatalf("local account id = %q, want local-alpha", snapshot.Accounts[0].CodexkitLocalAccountID)
	}
	if snapshot.Accounts[1].QuotaRefreshStatus != quotaRefreshStatusStale {
		t.Fatalf("second account status = %q, want %q", snapshot.Accounts[1].QuotaRefreshStatus, quotaRefreshStatusStale)
	}
	if snapshot.Accounts[2].QuotaRefreshStatus != quotaRefreshStatusUnavailable {
		t.Fatalf("third account status = %q, want %q", snapshot.Accounts[2].QuotaRefreshStatus, quotaRefreshStatusUnavailable)
	}
}

func TestBuildAuthFileEntryIncludesCodexkitLocalAccountID(t *testing.T) {
	handler := &Handler{}
	auth := &coreauth.Auth{
		ID:       "codex-alpha.json",
		FileName: "codex-alpha.json",
		Provider: "codex",
		Attributes: map[string]string{
			"path": "/tmp/codex-alpha.json",
		},
		Metadata: map[string]any{
			"email":                     "alpha@example.com",
			"codexkit_local_account_id": "local-alpha",
		},
	}

	entry := handler.buildAuthFileEntry(auth)
	if got, _ := entry["codexkit_local_account_id"].(string); got != "local-alpha" {
		t.Fatalf("codexkit_local_account_id = %q, want local-alpha", got)
	}
}

func TestMergeRefreshedAuthCopiesLatestMetadata(t *testing.T) {
	target := &coreauth.Auth{
		ID: "codex-alpha.json",
		Metadata: map[string]any{
			"access_token": "stale-access",
		},
	}
	refreshedAt := time.Date(2026, 4, 21, 14, 30, 0, 0, time.UTC)
	source := &coreauth.Auth{
		ID: "codex-alpha.json",
		Metadata: map[string]any{
			"access_token":  "fresh-access",
			"refresh_token": "fresh-refresh",
			"account_id":    "acct-openai-alpha",
		},
		UpdatedAt:       refreshedAt,
		LastRefreshedAt: refreshedAt,
	}

	mergeRefreshedAuth(target, source)

	if got := stringMetadataValue(target.Metadata, "access_token"); got != "fresh-access" {
		t.Fatalf("access_token = %q, want fresh-access", got)
	}
	if got := stringMetadataValue(target.Metadata, "refresh_token"); got != "fresh-refresh" {
		t.Fatalf("refresh_token = %q, want fresh-refresh", got)
	}
	if !target.UpdatedAt.Equal(refreshedAt) {
		t.Fatalf("updated_at = %v, want %v", target.UpdatedAt, refreshedAt)
	}
	if !target.LastRefreshedAt.Equal(refreshedAt) {
		t.Fatalf("last_refreshed_at = %v, want %v", target.LastRefreshedAt, refreshedAt)
	}
}
