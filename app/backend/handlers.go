package main

import (
	"encoding/json"
	"net/http"
	"strings"
)

func (s *Store) RegisterRoutes(mux *http.ServeMux, version string, buildTime string) {
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/api/data", handleData(version, buildTime))
	mux.HandleFunc("/api/transactions", s.handleTransactions)
	mux.HandleFunc("/api/transactions/", s.handleTransactionByID)
	mux.HandleFunc("/api/limits", s.handleLimits)
	mux.HandleFunc("/api/categories", s.handleCategories)
	mux.HandleFunc("/api/summary", s.handleSummary)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func handleData(version, buildTime string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"version":   version,
			"buildTime": buildTime,
		})
	}
}

func (s *Store) handleTransactions(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.GetTransactions())
	case http.MethodPost:
		var req TransactionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
			return
		}
		if req.Description == "" || req.Amount <= 0 || req.Category == "" || (req.Type != "income" && req.Type != "expense") {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "description, positive amount, category, and type (income|expense) are required"})
			return
		}
		t := s.AddTransaction(req)
		writeJSON(w, http.StatusCreated, t)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Store) handleTransactionByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/transactions/")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id required"})
		return
	}
	if !s.DeleteTransaction(id) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "transaction not found"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Store) handleLimits(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.GetLimits())
	case http.MethodPost:
		var req struct {
			Category string  `json:"category"`
			Limit    float64 `json:"limit"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
			return
		}
		if req.Category == "" || req.Limit < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "category and non-negative limit are required"})
			return
		}
		s.SetLimit(req.Category, req.Limit)
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Store) handleCategories(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, http.StatusOK, s.GetCategories())
}

func (s *Store) handleSummary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	transactions := s.GetTransactions()
	limits := s.GetLimits()
	writeJSON(w, http.StatusOK, ComputeSummary(transactions, limits))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
