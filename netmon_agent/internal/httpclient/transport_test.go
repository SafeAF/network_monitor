package httpclient

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestTransportRefusesRedirects(t *testing.T) {
	var received atomic.Int32
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
	}))
	defer destination.Close()
	source := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, destination.URL, http.StatusTemporaryRedirect)
	}))
	defer source.Close()
	client := New(source.URL, "token", 1, time.Second, nil, nil, 1, time.Second, 1, time.Second, 1, time.Second)
	client.httpClient.Transport = source.Client().Transport
	request, _ := http.NewRequest(http.MethodPost, source.URL, nil)
	request.Header.Set("Authorization", "Bearer token")
	response, err := client.httpClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusTemporaryRedirect || received.Load() != 0 {
		t.Fatal("client followed a redirect")
	}
}

func TestTransportVerifiesCertificates(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer server.Close()
	client := New(server.URL, "token", 1, time.Second, nil, nil, 1, time.Second, 1, time.Second, 1, time.Second)
	response, err := client.httpClient.Get(server.URL)
	if err == nil {
		response.Body.Close()
		t.Fatal("accepted an untrusted TLS certificate")
	}
}
