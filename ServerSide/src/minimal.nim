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

    #just assing conn to players
    #added 2 cuz was not sure if it crashes
    #on only 1 connection termination
    if players[0].conn == nil:
      players[0].conn = ws
    elif players[1].conn == nil:
      players[1].conn = ws

    while ws.readyState == Open:
      try:
        #CRASHES THE APP WHEN BEHIND NGINX
        #let fut = await ws.receiveStrPacket()

        #WOKRS WHEN BEHIND NGINX
        var fut = ws.receiveStrPacket()
        yield fut
        if fut.failed:
          echo "incoming stream error of doom"
          echo fut.error.msg
      except:
        echo "incoming stream error"


#just spam some msg all time
var num = 0;
proc spamMsg(){.async,gcsafe.}=
    while true:
      await sleepAsync(1000)
      num = num + 1;
      echo "sending fart " & $num
      for p in players:
        if p.conn != nil and p.conn.readyState == Open:
          try:
            var fut = p.conn.send(" Fart " & $num)
            yield fut
            if fut.failed:
              echo "uber doom on send"
          except:
            echo "error on send"


#close p0 p1 connection
proc forceClose(){.async.}=
    await sleepAsync(10000)
    echo "Closing"
    for p in players:
      if p.conn != nil and p.conn.readyState == Open:
        try:
          p.conn.close()
        except:
          echo "error on close"


echo "starting"
asyncCheck spamMsg()
asyncCheck forceClose()
waitFor server.serve(Port(9011), cb)