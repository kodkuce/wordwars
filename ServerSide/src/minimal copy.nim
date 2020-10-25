{.experimental: "codeReordering".}
import asynchttpserver, asyncdispatch
import ws, os



type Player = ref object of RootObj
    id*:int
    conn*:WebSocket

var players:seq[Player] = @[]
players.add( Player( id:1, conn:nil ) )
players.add( Player( id:2, conn:nil ) )


var server = newAsyncHttpServer()
proc cb(req: Request) {.async, gcsafe.} =
  if req.url.path == "/ws":
    var ws = await newWebSocket(req)
    await ws.send("Welcome to simple echo server")
    if players[0].conn == nil:
      players[0].conn = ws
    elif players[1].conn == nil:
      players[1].conn = ws

    while ws.readyState == Open:
      try:
        let packet = await ws.receiveStrPacket()
        await ws.send(packet)
      except:
        echo "incoming stream error"
  else:
    await req.respond(Http404, "Not found")

var num = 0;
proc spamMsg(){.async.}=
    while true:
      await sleepAsync(1000)
      num = num + 1;
      echo "sending fart " & $num
      for p in players:
        if p.conn != nil and p.conn.readyState == Open:
          try:
            await p.conn.send(" Fart " & $num)
          except:
            echo "error on send"

proc forceClose(){.async.}=
    await sleepAsync(10000)
    echo "Closing"
    for p in players:
      if p.conn != nil and p.conn.readyState == Open:
        try:
          p.conn.close()
          #p.conn = nil
        except:
          echo "error on close"


echo "starting"
asyncCheck spamMsg()
asyncCheck forceClose()
waitFor server.serve(Port(9011), cb)