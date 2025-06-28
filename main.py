import speech_recognition as sr
import spotipy
from spotipy.oauth2 import SpotifyOAuth

# Настройки Spotify
SPOTIPY_CLIENT_ID = '5f9752e7bd744480a0102cc241866c7f'
SPOTIPY_CLIENT_SECRET = '5f366f0e5902481796067a8b7828bb88'
SPOTIPY_REDIRECT_URI = 'http://127.0.0.1:8000/callback'
SCOPE = 'user-modify-playback-state user-read-playback-state'

# Инициализация Spotify
sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
    client_id=SPOTIPY_CLIENT_ID,
    client_secret=SPOTIPY_CLIENT_SECRET,
    redirect_uri=SPOTIPY_REDIRECT_URI,
    scope=SCOPE))

def recognize_speech():
    r = sr.Recognizer()
    with sr.Microphone() as source:
        print("Слушаю...")
        audio = r.listen(source)
    
    try:
        text = r.recognize_google(audio, language="ru-RU")
        print(f"Вы сказали: {text}")
        return text.lower()
    except:
        return ""

def handle_command(command):
    if "некст" in command or 'next' in command:
        sp.next_track()
        return "Переключаю"
        
    elif "предыдущий" in command:
        sp.previous_track()
        return "Возвращаю"
        
    elif "пауза" in command:
        sp.pause_playback()
        return "Пауза"
        
    elif "продолжи" in command:
        sp.start_playback()
        return "Продолжаем"
        
    return "Не понял команду"

while True:
    command = recognize_speech()
    if "Джарвис" in command or "jarvis" in command or "джарвис" in command:
        response = handle_command(command)
        print(response)  # или озвучка через TTS