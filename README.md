# Jarvis Voice Assistant (Go + Python)

Голосовой ассистент для управления Spotify с помощью голосовых команд на русском языке.  
Основная логика реализована на Go, для распознавания речи используется Python-скрипт.

---

## Возможности

- Управление Spotify (следующий/предыдущий трек, пауза, продолжить) голосом
- Распознавание речи на русском языке через Python (`speech_recognition`)
- Кроссплатформенность (macOS, Linux, Windows)

---

## Требования

- Go 1.18+
- Python 3.8+ (желательно установленный через Homebrew на macOS)
- Spotify Developer аккаунт (client_id, client_secret, redirect_uri)
- Микрофон

---

## Установка

1. **Клонируйте репозиторий:**
   ```sh
   git clone <your-repo-url>
   cd jarvis
   ```

2. **Создайте и активируйте виртуальное окружение Python:**
   ```sh
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Установите зависимости Python:**
   ```sh
   pip install --upgrade pip
   pip install -r requirements.txt
   ```

4. **Установите зависимости Go:**
   ```sh
   go mod tidy
   ```

5. **Создайте файл `.secret` с вашими ключами Spotify:**
   ```sh
   export SPOTIPY_CLIENT_ID=ваш_client_id
   export SPOTIPY_CLIENT_SECRET=ваш_client_secret
   export SPOTIPY_REDIRECT_URI=ваш_redirect_uri
   ```
   Затем загрузите переменные:
   ```sh
   source .secret
   ```

---

## Запуск

1. **Активируйте виртуальное окружение Python:**
   ```sh
   source venv/bin/activate
   ```

2. **Запустите Go-приложение:**
   ```sh
   go run main.go
   ```

3. **Следуйте инструкциям в терминале:**
   - Пройдите авторизацию Spotify по ссылке.
   - Говорите команды в микрофон, когда появится приглашение.

---

## Примеры голосовых команд

- "Джарвис следующий" — следующий трек
- "Джарвис предыдущий" — предыдущий трек
- "Джарвис пауза" — поставить на паузу
- "Джарвис продолжи" — продолжить воспроизведение

---

## Важно

- Файл `.secret` и папку `venv/` не добавляйте в git (см. `.gitignore`).
- Для работы микрофона на macOS убедитесь, что Terminal имеет доступ к микрофону (Системные настройки → Конфиденциальность → Микрофон).

---

## Лицензия

MIT
