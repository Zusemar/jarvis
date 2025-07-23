package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"

	"net/http"

	"github.com/zmb3/spotify/v2"
	auth "github.com/zmb3/spotify/v2/auth"
)

var (
	redirectURI  = os.Getenv("SPOTIPY_REDIRECT_URI")
	clientID     = os.Getenv("SPOTIPY_CLIENT_ID")
	clientSecret = os.Getenv("SPOTIPY_CLIENT_SECRET")
	scope        = "user-modify-playback-state user-read-playback-state"
	state        = "abc123"
	ch           = make(chan *spotify.Client)
)

func main() {
	// Авторизация Spotify
	ctx := context.Background()
	authenticator := auth.New(
		auth.WithClientID(clientID),
		auth.WithClientSecret(clientSecret),
		auth.WithRedirectURL(redirectURI),
		auth.WithScopes(
			auth.ScopeUserModifyPlaybackState,
			auth.ScopeUserReadPlaybackState,
		),
	)

	// Запуск локального сервера для получения токена
	http.HandleFunc("/callback", completeAuth(authenticator))
	go http.ListenAndServe(":8000", nil)

	url := authenticator.AuthURL(state)
	fmt.Println("Откройте ссылку в браузере для авторизации:", url)

	client := <-ch

	// Основной цикл
	for {
		fmt.Print("Скажите команду: ")
		text, err := recognizeSpeech()
		if err != nil {
			fmt.Println("Ошибка распознавания:", err)
			continue
		}
		fmt.Println("Вы сказали:", text)
		text = strings.ToLower(strings.TrimSpace(text))

		if strings.Contains(text, "следующий") {
			client.Next(ctx)
			say("Переключаю")
		} else if strings.Contains(text, "предыдущий") {
			client.Previous(ctx)
			say("Возвращаю")
		} else if strings.Contains(text, "пауза") {
			client.Pause(ctx)
			say("Пауза")
		} else if strings.Contains(text, "продолжи") {
			client.Play(ctx)
			say("Продолжаем")
		} else if strings.Contains(text, "выход") {
			break
		} else {
			say("Не понял команду")
		}
	}
}

func completeAuth(authenticator *auth.Authenticator) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, err := authenticator.Token(r.Context(), state, r)
		if err != nil {
			http.Error(w, "Не удалось получить токен", http.StatusForbidden)
			log.Fatal(err)
		}
		client := spotify.New(authenticator.Client(r.Context(), token))
		fmt.Fprintf(w, "Авторизация успешна! Можете закрыть это окно.")
		ch <- client
	}
}

func recognizeSpeech() (string, error) {
	cmd := exec.Command("python3", "recognize.py")
	cmd.Dir = "."
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Println("stderr:", string(out))
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func say(text string) {
	// На macOS можно использовать команду say
	exec.Command("say", text).Run()
}
