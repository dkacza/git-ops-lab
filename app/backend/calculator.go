package main

type Transaction struct {
	ID          string  `json:"id"`
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
	Category    string  `json:"category"`
	Type        string  `json:"type"` // "income" or "expense"
	Date        string  `json:"date"`
}

type TransactionRequest struct {
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
	Category    string  `json:"category"`
	Type        string  `json:"type"`
	Date        string  `json:"date"`
}

type OverspendAlert struct {
	Category string  `json:"category"`
	Spent    float64 `json:"spent"`
	Limit    float64 `json:"limit"`
	Excess   float64 `json:"excess"`
}

type Summary struct {
	Balance        float64            `json:"balance"`
	TotalIncome    float64            `json:"totalIncome"`
	TotalExpenses  float64            `json:"totalExpenses"`
	ByCategory     map[string]float64 `json:"byCategory"`
	SavingsRate    float64            `json:"savingsRate"`
	LargestExpense *Transaction       `json:"largestExpense"`
	Overspend      []OverspendAlert   `json:"overspend"`
}

func ComputeBalance(transactions []Transaction) float64 {
	var balance float64
	for _, t := range transactions {
		if t.Type == "income" {
			balance += t.Amount
		} else {
			balance -= t.Amount
		}
	}
	return balance
}

func ComputeTotals(transactions []Transaction) (income float64, expenses float64) {
	for _, t := range transactions {
		if t.Type == "income" {
			income += t.Amount
		} else {
			expenses += t.Amount
		}
	}
	return
}

func GroupByCategory(transactions []Transaction) map[string]float64 {
	result := make(map[string]float64)
	for _, t := range transactions {
		if t.Type == "expense" {
			result[t.Category] += t.Amount
		}
	}
	return result
}

func ComputeSavingsRate(transactions []Transaction) float64 {
	income, expenses := ComputeTotals(transactions)
	if income == 0 {
		return 0
	}
	savings := income - expenses
	if savings < 0 {
		return 0
	}
	return (savings / income) * 100
}

func FindLargestExpense(transactions []Transaction) *Transaction {
	var largest *Transaction
	for i, t := range transactions {
		if t.Type != "expense" {
			continue
		}
		if largest == nil || t.Amount > largest.Amount {
			largest = &transactions[i]
		}
	}
	return largest
}

func DetectOverspend(transactions []Transaction, limits map[string]float64) []OverspendAlert {
	byCategory := GroupByCategory(transactions)
	alerts := []OverspendAlert{}
	for category, limit := range limits {
		spent := byCategory[category]
		if spent > limit {
			alerts = append(alerts, OverspendAlert{
				Category: category,
				Spent:    spent,
				Limit:    limit,
				Excess:   spent - limit,
			})
		}
	}
	return alerts
}

func ComputeSummary(transactions []Transaction, limits map[string]float64) Summary {
	income, expenses := ComputeTotals(transactions)
	return Summary{
		Balance:        ComputeBalance(transactions),
		TotalIncome:    income,
		TotalExpenses:  expenses,
		ByCategory:     GroupByCategory(transactions),
		SavingsRate:    ComputeSavingsRate(transactions),
		LargestExpense: FindLargestExpense(transactions),
		Overspend:      DetectOverspend(transactions, limits),
	}
}
