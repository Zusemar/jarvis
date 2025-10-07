package spotifyApi

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"

	spot "github.com/zmb3/spotify/v2"
	spotauth "github.com/zmb3/spotify/v2/auth"
)

type Client struct {
	client *spot.Client
	ctx    context.Context
}

func NewClientFromEnv() (*Client, error) {
	clientID := os.Getenv("SPOTIPY_CLIENT_ID")
	clientSecret := os.Getenv("SPOTIPY_CLIENT_SECRET")
	redirectURI := os.Getenv("SPOTIPY_REDIRECT_URI")
	state := "abc123"

	ctx := context.Background()
	authenticator := spotauth.New(
		spotauth.WithClientID(clientID),
		spotauth.WithClientSecret(clientSecret),
		spotauth.WithRedirectURL(redirectURI),
		spotauth.WithScopes(
			spotauth.ScopeUserModifyPlaybackState,
			spotauth.ScopeUserReadPlaybackState,
		),
	)

	ch := make(chan *spot.Client)
	go func() {
		http.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
			token, err := authenticator.Token(r.Context(), state, r)
			if err != nil {
				http.Error(w, "Не удалось получить токен", http.StatusForbidden)
				return
			}
			client := spot.New(authenticator.Client(r.Context(), token))
			fmt.Fprintf(w, "Авторизация успешна! Можете закрыть это окно.")
			ch <- client
		})
		http.ListenAndServe(":8000", nil)
	}()

	url := authenticator.AuthURL(state)
	fmt.Println("Откройте ссылку в браузере для авторизации:", url)
	client := <-ch

	return &Client{client: client, ctx: ctx}, nil
}

func (c *Client) Next()     { c.client.Next(c.ctx) }
func (c *Client) Previous() { c.client.Previous(c.ctx) }
func (c *Client) Pause()    { c.client.Pause(c.ctx) }
func (c *Client) Play()     { c.client.Play(c.ctx) }

func (c *Client) PlayTrackByName(name string) error {
	result, err := c.client.Search(c.ctx, name, spot.SearchTypeTrack, spot.Limit(1))
	if err != nil {
		return err
	}
	if result.Tracks == nil || len(result.Tracks.Tracks) == 0 {
		return errors.New("track not found")
	}

	trackURI := result.Tracks.Tracks[0].URI
	return c.client.PlayOpt(c.ctx, &spot.PlayOptions{URIs: []spot.URI{trackURI}})
}

func (c *Client) PlayPlaylistByName(name string) error {
	result, err := c.client.Search(c.ctx, name, spot.SearchTypePlaylist, spot.Limit(1))
	if err != nil {
		return err
	}
	if result.Playlists == nil || len(result.Playlists.Playlists) == 0 {
		return errors.New("playlist not found")
	}

	playlistURI := result.Playlists.Playlists[0].URI
	return c.client.PlayOpt(c.ctx, &spot.PlayOptions{PlaybackContext: &playlistURI})
}

func IsNextCommand(text string) bool  { return strings.Contains(text, "следующий") }
func IsPrevCommand(text string) bool  { return strings.Contains(text, "предыдущий") }
func IsPauseCommand(text string) bool { return strings.Contains(text, "пауза") }
func IsPlayCommand(text string) bool  { return strings.Contains(text, "продолжи") }
func IsExitCommand(text string) bool  { return strings.Contains(text, "выход") }

func ParsePlayTrackCommand(text string) (string, bool) {
	prefixes := []string{
		"включи трек",
		"включить трек",
		"включи песню",
		"включить песню",
	}
	return parseNamedCommand(text, prefixes)
}

func ParsePlayPlaylistCommand(text string) (string, bool) {
	prefixes := []string{
		"включи плейлист",
		"включить плейлист",
		"включи подборку",
		"включить подборку",
	}
	return parseNamedCommand(text, prefixes)
}

func parseNamedCommand(text string, prefixes []string) (string, bool) {
	cleaned := strings.TrimSpace(text)
	lower := strings.ToLower(cleaned)
	lowerRunes := []rune(lower)
	textRunes := []rune(cleaned)

	for _, prefix := range prefixes {
		prefix = strings.TrimSpace(prefix)
		prefixRunes := []rune(prefix)
		if len(lowerRunes) < len(prefixRunes) {
			continue
		}
		if string(lowerRunes[:len(prefixRunes)]) != prefix {
			continue
		}
		remainder := strings.TrimSpace(string(textRunes[len(prefixRunes):]))
		if remainder == "" {
			continue
		}
		return remainder, true
	}

	return "", false
}
