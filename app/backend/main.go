package main

import (
	"log"
	"net/http"
	"os"
)

var (
	version   = "dev"
	buildTime = "unknown"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	store := NewStore()
	mux := http.NewServeMux()
	store.RegisterRoutes(mux, version, buildTime)

	handler := corsMiddleware(mux)

	log.Printf("budget-tracker backend version=%s buildTime=%s port=%s", version, buildTime, port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
