package httpclient

import (
	"encoding/json"
	"errors"
	"fmt"
)

type permanentRejection struct {
	reason          string
	acknowledgement json.RawMessage
}

func (e *permanentRejection) Error() string { return e.reason }

// Fail closed on incomplete/legacy acknowledgements. A 2xx status alone never
// authorizes deleting queued telemetry. Results refer to original batch indices.
func checkAcknowledgement(payload, body []byte) error {
	var batch struct {
		Events []json.RawMessage `json:"events"`
	}
	if err := json.Unmarshal(payload, &batch); err != nil {
		return errors.New("invalid outgoing batch")
	}
	var ack struct {
		Version   int `json:"protocol_version"`
		Accepted  int `json:"accepted"`
		Rejected  int `json:"rejected"`
		Retryable int `json:"retryable"`
		Results   []struct {
			Index  *int   `json:"index"`
			Status string `json:"status"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &ack); err != nil {
		return errors.New("invalid acknowledgement JSON")
	}
	if ack.Version != 1 || len(ack.Results) != len(batch.Events) {
		return errors.New("incomplete or unsupported acknowledgement")
	}
	seen := make([]bool, len(batch.Events))
	accepted, rejected, retryable := 0, 0, 0
	for _, result := range ack.Results {
		if result.Index == nil || *result.Index < 0 || *result.Index >= len(seen) || seen[*result.Index] {
			return errors.New("invalid acknowledgement indices")
		}
		seen[*result.Index] = true
		switch result.Status {
		case "accepted", "duplicate":
			accepted++
		case "rejected":
			rejected++
		case "retryable":
			retryable++
		default:
			return errors.New("unknown acknowledgement status")
		}
	}
	if accepted != ack.Accepted || rejected != ack.Rejected || retryable != ack.Retryable {
		return errors.New("acknowledgement counts do not match outcomes")
	}
	if retryable > 0 {
		return fmt.Errorf("batch has %d retryable events", retryable)
	}
	if rejected > 0 {
		return &permanentRejection{reason: "rejected_events", acknowledgement: body}
	}
	return nil
}

func permanentHTTPRejection(status int, body []byte) error {
	if status != 400 && status != 413 && status != 422 {
		return errors.New("HTTP error")
	}
	var failure struct {
		Version   int    `json:"protocol_version"`
		Error     string `json:"error"`
		Retryable *bool  `json:"retryable"`
	}
	if json.Unmarshal(body, &failure) == nil && failure.Version == 1 && failure.Retryable != nil && !*failure.Retryable &&
		(failure.Error == "invalid_batch" || failure.Error == "payload_too_large") {
		return &permanentRejection{reason: failure.Error, acknowledgement: body}
	}
	return errors.New("unrecognized HTTP rejection")
}
