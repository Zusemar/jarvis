import speech_recognition as sr
import sys

r = sr.Recognizer()
with sr.Microphone() as source:
    print("Говорите...")
    audio = r.listen(source)
try:
    print(r.recognize_google(audio, language="ru-RU"))
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)
