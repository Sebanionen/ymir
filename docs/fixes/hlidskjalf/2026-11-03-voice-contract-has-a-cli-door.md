# The opt-in Swedish voice contract has a CLI door

The real-engine proof was placed under server/ despite being an explicitly
invoked CLI. With no importer it correctly failed the dead-code ward as a dead
server module. Move it to scripts/, retain its real voice handler import, and
wire npm run test:voice:contract as the public execution door. The how-to and
owning asset name that door. No allowlist or pretend unit test is introduced.

The proof still requires explicit private home, synthetic Swedish WAV and private
evidence settings, opens only an ephemeral loopback port, performs the actual
Whisper/approved-answer/Bengt chain, and captures no physical microphone.