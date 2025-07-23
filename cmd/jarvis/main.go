package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"jarvis/internal/speech"
	"jarvis/internal/spotifyApi"
)

func main() {
	spClient, err := spotifyApi.NewClientFromEnv()
	if err != nil {
		fmt.Println("Ошибка авторизации Spotify:", err)
		return
	}

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		fmt.Println("\nЗавершение работы.")
		os.Exit(0)
	}()

	for {
		fmt.Print("Скажите команду: ")
		text, err := speech.Recognize()
		if err != nil {
			fmt.Println("Ошибка распознавания:", err)
			continue
		}
		fmt.Println("Вы сказали:", text)

		switch {
		case spotifyApi.IsNextCommand(text):
			spClient.Next()
			speech.Say("Переключаю")
		case spotifyApi.IsPrevCommand(text):
			spClient.Previous()
			speech.Say("Возвращаю")
		case spotifyApi.IsPauseCommand(text):
			spClient.Pause()
			speech.Say("Пауза")
		case spotifyApi.IsPlayCommand(text):
			spClient.Play()
			speech.Say("Продолжаем")
		case spotifyApi.IsExitCommand(text):
			fmt.Println("Выход.")
			return
		default:
			speech.Say("Не понял команду")
		}
	}
}
