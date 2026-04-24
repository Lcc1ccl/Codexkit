package gemini

import (
	"fmt"
	"os"
	"strings"
)

const (
	ClientIDEnvKey     = "CLIPROXYAPI_GEMINI_OAUTH_CLIENT_ID"
	ClientSecretEnvKey = "CLIPROXYAPI_GEMINI_OAUTH_CLIENT_SECRET"
)

func OAuthClientCredentials() (string, string, error) {
	clientID := strings.TrimSpace(os.Getenv(ClientIDEnvKey))
	clientSecret := strings.TrimSpace(os.Getenv(ClientSecretEnvKey))
	if clientID == "" || clientSecret == "" {
		return "", "", fmt.Errorf(
			"gemini oauth credentials are not configured; set %s and %s",
			ClientIDEnvKey,
			ClientSecretEnvKey,
		)
	}
	return clientID, clientSecret, nil
}
