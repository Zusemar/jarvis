# Использование секретов

1. Создайте файл `.secret` в папке `jarvis` со следующим содержимым:

```
SPOTIPY_CLIENT_ID=ваш_client_id
SPOTIPY_CLIENT_SECRET=ваш_client_secret
SPOTIPY_REDIRECT_URI=ваш_redirect_uri
SPOTIPY_SCOPE=user-modify-playback-state user-read-playback-state
```

2. Перед запуском main.py загрузите переменные окружения:

```sh
set -a
source jarvis/.secret
set +a
```

3. Запустите скрипт:

```sh
python jarvis/main.py
``` 