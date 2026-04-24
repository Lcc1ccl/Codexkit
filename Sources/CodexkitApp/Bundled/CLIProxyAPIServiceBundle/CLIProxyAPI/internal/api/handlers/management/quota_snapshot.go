package management

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	codexauth "github.com/router-for-me/CLIProxyAPI/v6/internal/auth/codex"
	"github.com/router-for-me/CLIProxyAPI/v6/internal/util"
	coreauth "github.com/router-for-me/CLIProxyAPI/v6/sdk/cliproxy/auth"
	log "github.com/sirupsen/logrus"
)

const (
	quotaSnapshotMetadataKey      = "quota_snapshot"
	quotaSnapshotSourceService    = "service"
	quotaRefreshStatusOK          = "ok"
	quotaRefreshStatusStale       = "stale"
	quotaRefreshStatusFailed      = "failed"
	quotaRefreshStatusUnavailable = "unavailable"
	quotaRefreshIntervalSeconds   = 60
	quotaStaleThresholdSeconds    = 120
	codexWhamUsageURL             = "https://chatgpt.com/backend-api/wham/usage"
)

type managementQuotaResponse struct {
	SnapshotGeneratedAt   time.Time                        `json:"snapshot_generated_at"`
	RefreshStatus         string                           `json:"refresh_status"`
	Stale                 bool                             `json:"stale"`
	RefreshIntervalSecond int                              `json:"refresh_interval_seconds"`
	StaleThresholdSecond  int                              `json:"stale_threshold_seconds"`
	Accounts              []managementQuotaAccountResponse `json:"accounts"`
}

type managementQuotaAccountResponse struct {
	ID                          string     `json:"id"`
	AuthIndex                   string     `json:"auth_index"`
	Name                        string     `json:"name"`
	Provider                    string     `json:"provider"`
	Email                       string     `json:"email"`
	Priority                    *int       `json:"priority"`
	ChatGPTAccountID            string     `json:"chatgpt_account_id"`
	CodexkitLocalAccountID      string     `json:"codexkit_local_account_id"`
	PlanType                    string     `json:"plan_type"`
	FiveHourRemainingPercent    *int       `json:"five_hour_remaining_percent"`
	WeeklyRemainingPercent      *int       `json:"weekly_remaining_percent"`
	PrimaryResetAt              *time.Time `json:"primary_reset_at"`
	SecondaryResetAt            *time.Time `json:"secondary_reset_at"`
	PrimaryLimitWindowSeconds   *int       `json:"primary_limit_window_seconds"`
	SecondaryLimitWindowSeconds *int       `json:"secondary_limit_window_seconds"`
	LastQuotaRefreshedAt        *time.Time `json:"last_quota_refreshed_at"`
	QuotaRefreshStatus          string     `json:"quota_refresh_status"`
	QuotaRefreshError           *string    `json:"quota_refresh_error"`
	QuotaSource                 string     `json:"quota_source"`
}

type quotaSnapshotMetadata struct {
	PlanType                    string     `json:"plan_type"`
	FiveHourRemainingPercent    *int       `json:"five_hour_remaining_percent"`
	WeeklyRemainingPercent      *int       `json:"weekly_remaining_percent"`
	PrimaryResetAt              *time.Time `json:"primary_reset_at"`
	SecondaryResetAt            *time.Time `json:"secondary_reset_at"`
	PrimaryLimitWindowSeconds   *int       `json:"primary_limit_window_seconds"`
	SecondaryLimitWindowSeconds *int       `json:"secondary_limit_window_seconds"`
	LastQuotaRefreshedAt        *time.Time `json:"last_quota_refreshed_at"`
	QuotaRefreshStatus          string     `json:"quota_refresh_status"`
	QuotaRefreshError           *string    `json:"quota_refresh_error"`
	QuotaSource                 string     `json:"quota_source"`
}

type codexWhamUsageResponse struct {
	PlanType  string `json:"plan_type"`
	RateLimit struct {
		PrimaryWindow   codexWhamUsageWindow `json:"primary_window"`
		SecondaryWindow codexWhamUsageWindow `json:"secondary_window"`
	} `json:"rate_limit"`
}

type codexWhamUsageWindow struct {
	UsedPercent        float64 `json:"used_percent"`
	ResetAt            float64 `json:"reset_at"`
	LimitWindowSeconds int     `json:"limit_window_seconds"`
}

func (h *Handler) GetQuotaSnapshot(c *gin.Context) {
	c.JSON(http.StatusOK, h.buildQuotaSnapshotResponse(time.Now().UTC(), h.listAuths()))
}

func (h *Handler) RefreshQuotaSnapshot(c *gin.Context) {
	snapshot, err := h.refreshQuotaSnapshots(c.Request.Context())
	if err != nil {
		log.WithError(err).Warn("quota snapshot refresh completed with errors")
	}
	c.JSON(http.StatusOK, snapshot)
}

func (h *Handler) startQuotaSnapshotRefreshLoop() {
	go func() {
		_, err := h.refreshQuotaSnapshots(context.Background())
		if err != nil {
			log.WithError(err).Debug("initial quota snapshot refresh incomplete")
		}

		ticker := time.NewTicker(time.Duration(quotaRefreshIntervalSeconds) * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if _, err := h.refreshQuotaSnapshots(context.Background()); err != nil {
				log.WithError(err).Debug("scheduled quota snapshot refresh incomplete")
			}
		}
	}()
}

func (h *Handler) refreshQuotaSnapshots(ctx context.Context) (managementQuotaResponse, error) {
	auths := h.listAuths()
	now := time.Now().UTC()
	var refreshErrs []string

	for _, auth := range auths {
		updatedAuth, err := h.refreshQuotaSnapshotForAuth(ctx, auth)
		if err != nil {
			refreshErrs = append(refreshErrs, err.Error())
		}
		if updatedAuth == nil || h.authManager == nil {
			continue
		}
		if _, err = h.authManager.Update(ctx, updatedAuth); err != nil {
			refreshErrs = append(refreshErrs, err.Error())
		}
	}

	snapshot := h.buildQuotaSnapshotResponse(now, h.listAuths())
	if len(refreshErrs) == 0 {
		return snapshot, nil
	}
	return snapshot, fmt.Errorf("%s", strings.Join(refreshErrs, "; "))
}

func (h *Handler) refreshQuotaSnapshotForAuth(ctx context.Context, auth *coreauth.Auth) (*coreauth.Auth, error) {
	if auth == nil {
		return nil, nil
	}

	next := auth.Clone()
	if next == nil {
		return nil, nil
	}

	previous := quotaSnapshotFromMetadata(next.Metadata)
	switch strings.ToLower(strings.TrimSpace(next.Provider)) {
	case "codex":
		snapshot, err := h.collectCodexQuotaSnapshot(ctx, next)
		if err != nil {
			applyQuotaSnapshotToAuth(next, quotaSnapshotFailure(next, previous, err))
			return next, err
		}
		applyQuotaSnapshotToAuth(next, snapshot)
		return next, nil
	default:
		applyQuotaSnapshotToAuth(next, quotaSnapshotUnavailable(previous))
		return next, nil
	}
}

func (h *Handler) collectCodexQuotaSnapshot(ctx context.Context, auth *coreauth.Auth) (quotaSnapshotMetadata, error) {
	if auth == nil {
		return quotaSnapshotMetadata{}, fmt.Errorf("quota snapshot: auth is nil")
	}

	metadata := auth.Metadata
	if metadata == nil {
		metadata = make(map[string]any)
		auth.Metadata = metadata
	}

	accountID := firstNonEmptyString(
		stringPtr(stringMetadataValue(metadata, "account_id")),
		stringPtr(stringClaimValue(extractCodexIDTokenClaims(auth), "chatgpt_account_id")),
	)
	if accountID == "" {
		return quotaSnapshotMetadata{}, fmt.Errorf("quota snapshot: missing chatgpt account id for %s", auth.ID)
	}

	usage, refreshedAuth, err := h.fetchCodexQuotaUsage(ctx, auth, accountID, true)
	if refreshedAuth != nil {
		mergeRefreshedAuth(auth, refreshedAuth)
	}
	if err != nil {
		return quotaSnapshotMetadata{}, err
	}

	primaryRemaining := remainingPercentFromUsage(usage.RateLimit.PrimaryWindow.UsedPercent)
	weeklyRemaining := remainingPercentFromUsage(usage.RateLimit.SecondaryWindow.UsedPercent)
	now := time.Now().UTC()
	planType := firstNonEmptyString(
		stringPtr(strings.TrimSpace(usage.PlanType)),
		stringPtr(stringClaimValue(extractCodexIDTokenClaims(auth), "plan_type")),
	)

	return quotaSnapshotMetadata{
		PlanType:                    planType,
		FiveHourRemainingPercent:    primaryRemaining,
		WeeklyRemainingPercent:      weeklyRemaining,
		PrimaryResetAt:              unixSecondsPointer(usage.RateLimit.PrimaryWindow.ResetAt),
		SecondaryResetAt:            unixSecondsPointer(usage.RateLimit.SecondaryWindow.ResetAt),
		PrimaryLimitWindowSeconds:   intPointerIfPositive(usage.RateLimit.PrimaryWindow.LimitWindowSeconds),
		SecondaryLimitWindowSeconds: intPointerIfPositive(usage.RateLimit.SecondaryWindow.LimitWindowSeconds),
		LastQuotaRefreshedAt:        &now,
		QuotaRefreshStatus:          quotaRefreshStatusOK,
		QuotaRefreshError:           nil,
		QuotaSource:                 quotaSnapshotSourceService,
	}, nil
}

func (h *Handler) fetchCodexQuotaUsage(
	ctx context.Context,
	auth *coreauth.Auth,
	accountID string,
	allowTokenRefresh bool,
) (codexWhamUsageResponse, *coreauth.Auth, error) {
	var usage codexWhamUsageResponse
	if auth == nil {
		return usage, auth, fmt.Errorf("quota snapshot: auth is nil")
	}

	accessToken := stringMetadataValue(auth.Metadata, "access_token")
	if accessToken == "" && allowTokenRefresh {
		refreshed, err := h.refreshCodexAuth(ctx, auth)
		if err != nil {
			return usage, auth, err
		}
		auth = refreshed
		accessToken = stringMetadataValue(auth.Metadata, "access_token")
	}
	if accessToken == "" {
		return usage, auth, fmt.Errorf("quota snapshot: missing access token for %s", auth.ID)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, codexWhamUsageURL, nil)
	if err != nil {
		return usage, auth, err
	}
	request.Header.Set("Authorization", "Bearer "+accessToken)
	request.Header.Set("chatgpt-account-id", accountID)
	request.Header.Set("Accept", "*/*")
	request.Header.Set("oai-language", "zh-CN")
	request.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	request.Header.Set("Referer", "https://chatgpt.com/codex/settings/usage")

	httpClient := &http.Client{}
	if h != nil && h.cfg != nil {
		sdkCfg := h.cfg.SDKConfig
		if proxyURL := strings.TrimSpace(auth.ProxyURL); proxyURL != "" {
			sdkCfg.ProxyURL = proxyURL
		}
		httpClient = util.SetProxy(&sdkCfg, httpClient)
	}

	response, err := httpClient.Do(request)
	if err != nil {
		return usage, auth, err
	}
	defer func() {
		_ = response.Body.Close()
	}()

	switch response.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized:
		if !allowTokenRefresh {
			return usage, auth, fmt.Errorf("quota snapshot: unauthorized for %s", auth.ID)
		}
		refreshed, refreshErr := h.refreshCodexAuth(ctx, auth)
		if refreshErr != nil {
			return usage, auth, refreshErr
		}
		return h.fetchCodexQuotaUsage(ctx, refreshed, accountID, false)
	default:
		return usage, auth, fmt.Errorf("quota snapshot: usage request failed for %s with status %d", auth.ID, response.StatusCode)
	}

	if err = json.NewDecoder(response.Body).Decode(&usage); err != nil {
		return usage, auth, err
	}
	return usage, auth, nil
}

func (h *Handler) refreshCodexAuth(ctx context.Context, auth *coreauth.Auth) (*coreauth.Auth, error) {
	if auth == nil {
		return nil, fmt.Errorf("quota snapshot: auth is nil")
	}
	refreshToken := stringMetadataValue(auth.Metadata, "refresh_token")
	if refreshToken == "" {
		return auth, fmt.Errorf("quota snapshot: missing refresh token for %s", auth.ID)
	}

	service := codexauth.NewCodexAuthWithProxyURL(h.cfg, auth.ProxyURL)
	tokenData, err := service.RefreshTokensWithRetry(ctx, refreshToken, 3)
	if err != nil {
		return auth, err
	}

	next := auth.Clone()
	if next.Metadata == nil {
		next.Metadata = make(map[string]any)
	}
	next.Metadata["id_token"] = tokenData.IDToken
	next.Metadata["access_token"] = tokenData.AccessToken
	if tokenData.RefreshToken != "" {
		next.Metadata["refresh_token"] = tokenData.RefreshToken
	}
	if tokenData.AccountID != "" {
		next.Metadata["account_id"] = tokenData.AccountID
	}
	next.Metadata["email"] = tokenData.Email
	next.Metadata["expired"] = tokenData.Expire
	next.Metadata["last_refresh"] = time.Now().UTC().Format(time.RFC3339)
	next.Metadata["type"] = "codex"
	return next, nil
}

func (h *Handler) buildQuotaSnapshotResponse(now time.Time, auths []*coreauth.Auth) managementQuotaResponse {
	accounts := make([]managementQuotaAccountResponse, 0, len(auths))
	supportedCount := 0
	supportedFreshCount := 0
	supportedUsableCount := 0

	for _, auth := range auths {
		account := buildQuotaAccountResponse(auth, now)
		accounts = append(accounts, account)
		if strings.EqualFold(strings.TrimSpace(account.Provider), "codex") {
			supportedCount++
			if account.QuotaRefreshStatus == quotaRefreshStatusOK {
				supportedFreshCount++
			}
			if account.LastQuotaRefreshedAt != nil || account.FiveHourRemainingPercent != nil || account.WeeklyRemainingPercent != nil {
				supportedUsableCount++
			}
		}
	}

	sort.Slice(accounts, func(i, j int) bool {
		lhs := strings.ToLower(firstNonEmptyString(
			stringPtr(accounts[i].Email),
			stringPtr(accounts[i].Name),
			stringPtr(accounts[i].ID),
		))
		rhs := strings.ToLower(firstNonEmptyString(
			stringPtr(accounts[j].Email),
			stringPtr(accounts[j].Name),
			stringPtr(accounts[j].ID),
		))
		if lhs == rhs {
			return strings.ToLower(accounts[i].ID) < strings.ToLower(accounts[j].ID)
		}
		return lhs < rhs
	})

	refreshStatus := quotaRefreshStatusOK
	stale := false
	switch {
	case supportedCount == 0:
		refreshStatus = quotaRefreshStatusFailed
		stale = true
	case supportedFreshCount == supportedCount:
		refreshStatus = quotaRefreshStatusOK
	case supportedUsableCount > 0:
		refreshStatus = quotaRefreshStatusStale
		stale = true
	default:
		refreshStatus = quotaRefreshStatusFailed
		stale = true
	}

	return managementQuotaResponse{
		SnapshotGeneratedAt:   now,
		RefreshStatus:         refreshStatus,
		Stale:                 stale,
		RefreshIntervalSecond: quotaRefreshIntervalSeconds,
		StaleThresholdSecond:  quotaStaleThresholdSeconds,
		Accounts:              accounts,
	}
}

func buildQuotaAccountResponse(auth *coreauth.Auth, now time.Time) managementQuotaAccountResponse {
	if auth == nil {
		return managementQuotaAccountResponse{}
	}
	auth.EnsureIndex()
	snapshot := quotaSnapshotFromMetadata(auth.Metadata)
	status := normalizedQuotaStatus(snapshot, now)
	claims := extractCodexIDTokenClaims(auth)
	name := strings.TrimSpace(auth.FileName)
	if name == "" {
		name = strings.TrimSpace(auth.ID)
	}
	priority := authPriority(auth)

	return managementQuotaAccountResponse{
		ID:                          strings.TrimSpace(auth.ID),
		AuthIndex:                   strings.TrimSpace(auth.Index),
		Name:                        name,
		Provider:                    strings.TrimSpace(auth.Provider),
		Email:                       firstNonEmptyString(stringPtr(authEmail(auth)), stringPtr(stringMetadataValue(auth.Metadata, "email"))),
		Priority:                    priority,
		ChatGPTAccountID:            firstNonEmptyString(stringPtr(stringClaimValue(claims, "chatgpt_account_id")), stringPtr(stringMetadataValue(auth.Metadata, "account_id"))),
		CodexkitLocalAccountID:      stringMetadataValue(auth.Metadata, "codexkit_local_account_id"),
		PlanType:                    firstNonEmptyString(stringPtr(snapshot.PlanType), stringPtr(stringClaimValue(claims, "plan_type"))),
		FiveHourRemainingPercent:    snapshot.FiveHourRemainingPercent,
		WeeklyRemainingPercent:      snapshot.WeeklyRemainingPercent,
		PrimaryResetAt:              snapshot.PrimaryResetAt,
		SecondaryResetAt:            snapshot.SecondaryResetAt,
		PrimaryLimitWindowSeconds:   snapshot.PrimaryLimitWindowSeconds,
		SecondaryLimitWindowSeconds: snapshot.SecondaryLimitWindowSeconds,
		LastQuotaRefreshedAt:        snapshot.LastQuotaRefreshedAt,
		QuotaRefreshStatus:          status,
		QuotaRefreshError:           snapshot.QuotaRefreshError,
		QuotaSource:                 firstNonEmptyString(stringPtr(snapshot.QuotaSource), stringPtr(quotaSnapshotSourceService)),
	}
}

func quotaSnapshotFromMetadata(metadata map[string]any) quotaSnapshotMetadata {
	if metadata == nil {
		return quotaSnapshotMetadata{QuotaRefreshStatus: quotaRefreshStatusUnavailable}
	}
	raw, ok := metadata[quotaSnapshotMetadataKey]
	if !ok || raw == nil {
		return quotaSnapshotMetadata{QuotaRefreshStatus: quotaRefreshStatusUnavailable}
	}
	data, err := json.Marshal(raw)
	if err != nil {
		return quotaSnapshotMetadata{QuotaRefreshStatus: quotaRefreshStatusUnavailable}
	}
	var snapshot quotaSnapshotMetadata
	if err = json.Unmarshal(data, &snapshot); err != nil {
		return quotaSnapshotMetadata{QuotaRefreshStatus: quotaRefreshStatusUnavailable}
	}
	if strings.TrimSpace(snapshot.QuotaRefreshStatus) == "" {
		snapshot.QuotaRefreshStatus = quotaRefreshStatusUnavailable
	}
	return snapshot
}

func applyQuotaSnapshotToAuth(auth *coreauth.Auth, snapshot quotaSnapshotMetadata) {
	if auth == nil {
		return
	}
	if auth.Metadata == nil {
		auth.Metadata = make(map[string]any)
	}
	data, err := json.Marshal(snapshot)
	if err != nil {
		return
	}
	var raw map[string]any
	if err = json.Unmarshal(data, &raw); err != nil {
		return
	}
	auth.Metadata[quotaSnapshotMetadataKey] = raw
	auth.UpdatedAt = time.Now().UTC()
}

func mergeRefreshedAuth(target *coreauth.Auth, source *coreauth.Auth) {
	if target == nil || source == nil {
		return
	}
	clone := source.Clone()
	if clone == nil {
		return
	}
	target.Metadata = clone.Metadata
	target.UpdatedAt = clone.UpdatedAt
	target.LastRefreshedAt = clone.LastRefreshedAt
}

func quotaSnapshotFailure(auth *coreauth.Auth, previous quotaSnapshotMetadata, err error) quotaSnapshotMetadata {
	next := previous
	next.QuotaRefreshStatus = quotaRefreshStatusFailed
	next.QuotaSource = quotaSnapshotSourceService
	if err != nil {
		message := err.Error()
		next.QuotaRefreshError = &message
	}
	if next.LastQuotaRefreshedAt == nil {
		next.FiveHourRemainingPercent = nil
		next.WeeklyRemainingPercent = nil
		next.PrimaryResetAt = nil
		next.SecondaryResetAt = nil
		next.PrimaryLimitWindowSeconds = nil
		next.SecondaryLimitWindowSeconds = nil
	}
	if claims := extractCodexIDTokenClaims(auth); claims != nil && next.PlanType == "" {
		next.PlanType = stringClaimValue(claims, "plan_type")
	}
	return next
}

func quotaSnapshotUnavailable(previous quotaSnapshotMetadata) quotaSnapshotMetadata {
	next := previous
	next.QuotaRefreshStatus = quotaRefreshStatusUnavailable
	next.QuotaSource = quotaSnapshotSourceService
	next.QuotaRefreshError = nil
	return next
}

func normalizedQuotaStatus(snapshot quotaSnapshotMetadata, now time.Time) string {
	status := strings.ToLower(strings.TrimSpace(snapshot.QuotaRefreshStatus))
	switch status {
	case quotaRefreshStatusOK, quotaRefreshStatusStale, quotaRefreshStatusFailed, quotaRefreshStatusUnavailable:
	default:
		status = quotaRefreshStatusUnavailable
	}
	if status == quotaRefreshStatusOK && snapshot.LastQuotaRefreshedAt != nil {
		if now.Sub(snapshot.LastQuotaRefreshedAt.UTC()) > time.Duration(quotaStaleThresholdSeconds)*time.Second {
			return quotaRefreshStatusStale
		}
	}
	return status
}

func (h *Handler) listAuths() []*coreauth.Auth {
	if h == nil || h.authManager == nil {
		return nil
	}
	return h.authManager.List()
}

func authPriority(auth *coreauth.Auth) *int {
	if auth == nil {
		return nil
	}
	if raw := strings.TrimSpace(authAttribute(auth, "priority")); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			return &parsed
		}
	}
	if auth.Metadata == nil {
		return nil
	}
	switch value := auth.Metadata["priority"].(type) {
	case float64:
		parsed := int(value)
		return &parsed
	case int:
		return &value
	case string:
		if parsed, err := strconv.Atoi(strings.TrimSpace(value)); err == nil {
			return &parsed
		}
	}
	return nil
}

func stringMetadataValue(metadata map[string]any, key string) string {
	if metadata == nil {
		return ""
	}
	raw, ok := metadata[key]
	if !ok || raw == nil {
		return ""
	}
	value, ok := raw.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(value)
}

func stringClaimValue(claims gin.H, key string) string {
	if claims == nil {
		return ""
	}
	raw, ok := claims[key]
	if !ok || raw == nil {
		return ""
	}
	value, ok := raw.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(value)
}

func stringPtr(value string) *string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func remainingPercentFromUsage(usedPercent float64) *int {
	if math.IsNaN(usedPercent) || math.IsInf(usedPercent, 0) {
		return nil
	}
	remaining := int(math.Round(100 - usedPercent))
	if remaining < 0 {
		remaining = 0
	}
	if remaining > 100 {
		remaining = 100
	}
	return &remaining
}

func unixSecondsPointer(value float64) *time.Time {
	if value <= 0 {
		return nil
	}
	timestamp := time.Unix(int64(value), 0).UTC()
	return &timestamp
}

func intPointerIfPositive(value int) *int {
	if value <= 0 {
		return nil
	}
	result := value
	return &result
}
