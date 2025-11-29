package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"fmt"
	"strconv"
	"testing"
	"time"
)

func TestValidateSlackRequest(t *testing.T) {
	signingKey := "test-signing-key"
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	body := []byte(`{"type":"url_verification","challenge":"test"}`)

	// Generate valid signature
	baseString := fmt.Sprintf("v0:%s:%s", timestamp, string(body))
	h := hmac.New(sha256.New, []byte(signingKey))
	h.Write([]byte(baseString))
	validSig := "v0=" + fmt.Sprintf("%x", h.Sum(nil))

	tests := []struct {
		name      string
		body      []byte
		timestamp string
		signature string
		sigKey    string
		want      bool
	}{
		{
			name:      "valid signature",
			body:      body,
			timestamp: timestamp,
			signature: validSig,
			sigKey:    signingKey,
			want:      true,
		},
		{
			name:      "invalid signature",
			body:      body,
			timestamp: timestamp,
			signature: "v0=invalidsig",
			sigKey:    signingKey,
			want:      false,
		},
		{
			name:      "wrong signing key",
			body:      body,
			timestamp: timestamp,
			signature: validSig,
			sigKey:    "wrong-key",
			want:      false,
		},
		{
			name:      "old timestamp",
			body:      body,
			timestamp: strconv.FormatInt(time.Now().Unix()-400, 10), // 400 seconds old
			signature: validSig,
			sigKey:    signingKey,
			want:      false,
		},
		{
			name:      "invalid timestamp format",
			body:      body,
			timestamp: "not-a-number",
			signature: validSig,
			sigKey:    signingKey,
			want:      false,
		},
		{
			name:      "empty signature",
			body:      body,
			timestamp: timestamp,
			signature: "",
			sigKey:    signingKey,
			want:      false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ValidateSlackRequest(tt.body, tt.timestamp, tt.signature, tt.sigKey)
			if got != tt.want {
				t.Errorf("ValidateSlackRequest() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestValidateSlackRequestTimestampFreshness(t *testing.T) {
	signingKey := "test-key"

	// Test current timestamp
	now := time.Now().Unix()
	recentTS := strconv.FormatInt(now, 10)
	body := []byte("test")

	baseString := fmt.Sprintf("v0:%s:%s", recentTS, string(body))
	h := hmac.New(sha256.New, []byte(signingKey))
	h.Write([]byte(baseString))
	recentSig := "v0=" + fmt.Sprintf("%x", h.Sum(nil))

	if !ValidateSlackRequest(body, recentTS, recentSig, signingKey) {
		t.Error("ValidateSlackRequest() failed with recent timestamp")
	}

	// Test old timestamp (>5 minutes)
	oldTS := strconv.FormatInt(now-301, 10)
	if ValidateSlackRequest(body, oldTS, recentSig, signingKey) {
		t.Error("ValidateSlackRequest() should reject timestamp older than 5 minutes")
	}
}

func TestValidateSlackRequestConstantTimeComparison(t *testing.T) {
	signingKey := "test-key"
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	body := []byte("test")

	// Generate valid signature
	baseString := fmt.Sprintf("v0:%s:%s", timestamp, string(body))
	h := hmac.New(sha256.New, []byte(signingKey))
	h.Write([]byte(baseString))
	validSig := "v0=" + fmt.Sprintf("%x", h.Sum(nil))

	// Signature that's similar but wrong
	wrongSig := "v0=" + "0" + validSig[3:] // Change first char

	result := ValidateSlackRequest(body, timestamp, wrongSig, signingKey)
	if result {
		t.Error("ValidateSlackRequest() should reject similar but invalid signature")
	}
}
