package main

import (
	"fmt"
	"sync"
	"time"
)

var defaultCategories = []string{
	"Food", "Transport", "Housing", "Entertainment", "Health", "Other",
}

type Store struct {
	mu           sync.RWMutex
	transactions []Transaction
	limits       map[string]float64
	categories   []string
	nextID       int
}

func NewStore() *Store {
	return &Store{
		transactions: []Transaction{},
		limits:       make(map[string]float64),
		categories:   append([]string{}, defaultCategories...),
		nextID:       1,
	}
}

func (s *Store) AddTransaction(req TransactionRequest) Transaction {
	s.mu.Lock()
	defer s.mu.Unlock()

	t := Transaction{
		ID:          fmt.Sprintf("%d", s.nextID),
		Description: req.Description,
		Amount:      req.Amount,
		Category:    req.Category,
		Type:        req.Type,
		Date:        req.Date,
	}
	if t.Date == "" {
		t.Date = time.Now().Format("2006-01-02")
	}
	s.nextID++
	s.transactions = append(s.transactions, t)

	if !s.hasCategory(req.Category) {
		s.categories = append(s.categories, req.Category)
	}

	return t
}

func (s *Store) DeleteTransaction(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	for i, t := range s.transactions {
		if t.ID == id {
			s.transactions = append(s.transactions[:i], s.transactions[i+1:]...)
			return true
		}
	}
	return false
}

func (s *Store) GetTransactions() []Transaction {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]Transaction, len(s.transactions))
	copy(result, s.transactions)
	return result
}

func (s *Store) SetLimit(category string, limit float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.limits[category] = limit
}

func (s *Store) GetLimits() map[string]float64 {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make(map[string]float64)
	for k, v := range s.limits {
		result[k] = v
	}
	return result
}

func (s *Store) GetCategories() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]string, len(s.categories))
	copy(result, s.categories)
	return result
}

func (s *Store) hasCategory(name string) bool {
	for _, c := range s.categories {
		if c == name {
			return true
		}
	}
	return false
}