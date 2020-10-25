import ws, asyncdispatch, asynchttpserver


type
  PlayerConnections = ref object of RootObj
    authed:bool
    nick:string
    wtf:int
    

var server = newAsyncHttpServer()

proc cb(req: Request) {.async.} =
  echo req.headers
  echo req.headers["sec-websocket-protocol"]

  #req.headers["sec-websocket-protocol"] = ""
  #echo "changed hdear"
  try:

    if req.url.path == "/ws":
      var ws = await newWebSocket(req)
      await ws.send("Welcome to sissmple echo server")



      while ws.readyState == Open:
        let packet = await ws.receivePacket()
        echo packet

  except:
    echo getCurrentExceptionMsg()


  await req.respond(Http200, "Hello World")

waitFor server.serve(Port(9001), cb)
