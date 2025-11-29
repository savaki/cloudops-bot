package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"fmt"
	"log"
	"strconv"
	"time"
)

// ValidateSlackRequest validates the Slack request signature
// This ensures the request came from Slack
// See: https://api.slack.com/authentication/verifying-requests-from-slack
func ValidateSlackRequest(body []byte, timestamp string, signature string, signingKey string) bool {
	// Validate timestamp is recent (not older than 5 minutes)
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		log.Printf("Invalid timestamp: %s", timestamp)
		return false
	}

	now := time.Now().Unix()
	if now-ts > 300 { // 5 minutes
		log.Printf("Request timestamp too old: %d (current: %d)", ts, now)
		return false
	}

	// Create signature base string: v0:<timestamp>:<body>
	baseString := fmt.Sprintf("v0:%s:%s", timestamp, string(body))

	// Create HMAC SHA256 hash
	h := hmac.New(sha256.New, []byte(signingKey))
	h.Write([]byte(baseString))
	expectedSig := "v0=" + fmt.Sprintf("%x", h.Sum(nil))

	// Compare with provided signature using constant-time comparison
	if !hmac.Equal([]byte(expectedSig), []byte(signature)) {
		log.Printf("Invalid signature. Expected: %s, Got: %s", expectedSig, signature)
		return false
	}

	log.Printf("Slack request signature validated successfully")
	return true
}
