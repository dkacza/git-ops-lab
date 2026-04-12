package main

import (
	"testing"
)

func makeTransactions() []Transaction {
	return []Transaction{
		{ID: "1", Description: "Salary", Amount: 3000, Category: "Income", Type: "income", Date: "2024-01-01"},
		{ID: "2", Description: "Rent", Amount: 800, Category: "Housing", Type: "expense", Date: "2024-01-02"},
		{ID: "3", Description: "Groceries", Amount: 200, Category: "Food", Type: "expense", Date: "2024-01-03"},
		{ID: "4", Description: "Bus pass", Amount: 50, Category: "Transport", Type: "expense", Date: "2024-01-04"},
		{ID: "5", Description: "Dinner out", Amount: 120, Category: "Food", Type: "expense", Date: "2024-01-05"},
	}
}

// --- ComputeBalance ---

func TestComputeBalance_Normal(t *testing.T) {
	txs := makeTransactions()
	// income: 3000, expenses: 800+200+50+120 = 1170
	got := ComputeBalance(txs)
	want := 1830.0
	if got != want {
		t.Errorf("ComputeBalance = %.2f, want %.2f", got, want)
	}
}

func TestComputeBalance_Empty(t *testing.T) {
	got := ComputeBalance([]Transaction{})
	if got != 0 {
		t.Errorf("ComputeBalance empty = %.2f, want 0", got)
	}
}

func TestComputeBalance_OnlyExpenses(t *testing.T) {
	txs := []Transaction{
		{Type: "expense", Amount: 100},
		{Type: "expense", Amount: 50},
	}
	got := ComputeBalance(txs)
	if got != -150 {
		t.Errorf("ComputeBalance only expenses = %.2f, want -150", got)
	}
}

func TestComputeBalance_OnlyIncome(t *testing.T) {
	txs := []Transaction{
		{Type: "income", Amount: 500},
		{Type: "income", Amount: 250},
	}
	got := ComputeBalance(txs)
	if got != 750 {
		t.Errorf("ComputeBalance only income = %.2f, want 750", got)
	}
}

// --- GroupByCategory ---

func TestGroupByCategory_Normal(t *testing.T) {
	txs := makeTransactions()
	got := GroupByCategory(txs)

	if got["Food"] != 320 {
		t.Errorf("Food = %.2f, want 320", got["Food"])
	}
	if got["Housing"] != 800 {
		t.Errorf("Housing = %.2f, want 800", got["Housing"])
	}
	if got["Transport"] != 50 {
		t.Errorf("Transport = %.2f, want 50", got["Transport"])
	}
}

func TestGroupByCategory_IgnoresIncome(t *testing.T) {
	txs := makeTransactions()
	got := GroupByCategory(txs)
	if _, ok := got["Income"]; ok {
		t.Error("GroupByCategory should not include income entries")
	}
}

func TestGroupByCategory_Empty(t *testing.T) {
	got := GroupByCategory([]Transaction{})
	if len(got) != 0 {
		t.Errorf("expected empty map, got %v", got)
	}
}

// --- ComputeSavingsRate ---

func TestComputeSavingsRate_Normal(t *testing.T) {
	txs := makeTransactions()
	// income 3000, expenses 1170, savings 1830, rate = 61%
	got := ComputeSavingsRate(txs)
	want := (1830.0 / 3000.0) * 100
	if got != want {
		t.Errorf("SavingsRate = %.2f, want %.2f", got, want)
	}
}

func TestComputeSavingsRate_NoIncome(t *testing.T) {
	txs := []Transaction{
		{Type: "expense", Amount: 100},
	}
	got := ComputeSavingsRate(txs)
	if got != 0 {
		t.Errorf("SavingsRate with no income = %.2f, want 0", got)
	}
}

func TestComputeSavingsRate_NegativeSavings(t *testing.T) {
	txs := []Transaction{
		{Type: "income", Amount: 100},
		{Type: "expense", Amount: 200},
	}
	got := ComputeSavingsRate(txs)
	if got != 0 {
		t.Errorf("SavingsRate when spending exceeds income = %.2f, want 0", got)
	}
}

func TestComputeSavingsRate_FullSavings(t *testing.T) {
	txs := []Transaction{
		{Type: "income", Amount: 1000},
	}
	got := ComputeSavingsRate(txs)
	if got != 100 {
		t.Errorf("SavingsRate 100%% = %.2f, want 100", got)
	}
}

// --- FindLargestExpense ---

func TestFindLargestExpense_Normal(t *testing.T) {
	txs := makeTransactions()
	got := FindLargestExpense(txs)
	if got == nil {
		t.Fatal("expected a transaction, got nil")
	}
	if got.Description != "Rent" {
		t.Errorf("LargestExpense = %s, want Rent", got.Description)
	}
}

func TestFindLargestExpense_Empty(t *testing.T) {
	got := FindLargestExpense([]Transaction{})
	if got != nil {
		t.Errorf("expected nil for empty list, got %v", got)
	}
}

func TestFindLargestExpense_OnlyIncome(t *testing.T) {
	txs := []Transaction{
		{Type: "income", Amount: 5000, Description: "Salary"},
	}
	got := FindLargestExpense(txs)
	if got != nil {
		t.Errorf("expected nil when no expenses, got %v", got)
	}
}

// --- DetectOverspend ---

func TestDetectOverspend_Triggered(t *testing.T) {
	txs := makeTransactions() // Food = 320
	limits := map[string]float64{"Food": 300}
	alerts := DetectOverspend(txs, limits)
	if len(alerts) != 1 {
		t.Fatalf("expected 1 alert, got %d", len(alerts))
	}
	if alerts[0].Category != "Food" {
		t.Errorf("alert category = %s, want Food", alerts[0].Category)
	}
	if alerts[0].Excess != 20 {
		t.Errorf("excess = %.2f, want 20", alerts[0].Excess)
	}
}

func TestDetectOverspend_NotTriggered(t *testing.T) {
	txs := makeTransactions() // Food = 320
	limits := map[string]float64{"Food": 500}
	alerts := DetectOverspend(txs, limits)
	if len(alerts) != 0 {
		t.Errorf("expected no alerts, got %d", len(alerts))
	}
}

func TestDetectOverspend_NoLimits(t *testing.T) {
	txs := makeTransactions()
	alerts := DetectOverspend(txs, map[string]float64{})
	if len(alerts) != 0 {
		t.Errorf("expected no alerts with no limits, got %d", len(alerts))
	}
}

func TestDetectOverspend_ExactLimit(t *testing.T) {
	txs := makeTransactions() // Food = 320
	limits := map[string]float64{"Food": 320}
	alerts := DetectOverspend(txs, limits)
	if len(alerts) != 0 {
		t.Errorf("expected no alert at exact limit, got %d", len(alerts))
	}
}
