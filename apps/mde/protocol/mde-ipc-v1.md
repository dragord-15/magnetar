# MDE IPC v1 (MVP)

Transport: Unix domain stream socket, JSON object per line (`\n` delimited UTF-8).

## Socket paths

- Dev mode: `/tmp/mde-<uid>/compositor.sock`
- Target: `/run/user/<uid>/mde/compositor.sock`

## Message envelope

Request:
```json
{"t":"req","id":1,"method":"hello","params":{"role":"app","name":"mde-hello"}}
```

Response:
```json
{"t":"res","id":1,"ok":true,"result":{"session":"mde","version":1}}
```

Event:
```json
{"t":"evt","event":"window.focus","params":{"window_id":2}}
```

Error:
```json
{"t":"res","id":1,"ok":false,"error":{"code":"bad_request","message":"missing method"}}
```

## MVP methods

- `hello` -> `{version,session}`
- `ping` -> `{pong:true}`
- `window.create` params `{title,w,h}` -> `{window_id}`
- `window.close` params `{window_id}` -> `{closed:true}`
- `app.launch` params `{exec}` -> `{pid}` (session/panel use; compositor may reject)
- `session.quit` -> `{quitting:true}`

## Roles

- `compositor`: owns display and window list
- `session`: supervises processes
- `panel`, `launcher`, `app`: clients

MVP note: compositor currently embeds panel/launcher behavior in dev mode; IPC is specified now so components can be split next.
