# Windows voice restart preserves Unicode answers

The local voice API could transcribe and answer but fail before speech after a
restart: its child Python received PYTHONIOENCODING=utf-8, while the parent
cleaner subprocess used Windows locale encoding for text=True pipes. Accented
letters in answers produced a real UnicodeDecodeError in speech-text.py.

voice-io.py now specifies encoding=utf-8 on the cleaner subprocess. The focused
regression invokes the real cleaner with an accented answer and the API's UTF-8
environment, then validates the resulting synthesis payload and WAV publication.
The installed engines, genuine Swedish voice and microphone consent are unchanged.