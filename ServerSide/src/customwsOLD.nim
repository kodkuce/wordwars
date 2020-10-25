import asyncdispatch, asynchttpserver, asyncnet, base64, httpclient, httpcore,
    nativesockets, net, random, std/sha1, streams, strformat, strutils, uri, ws, sequtils


proc newWebSocketWithCustomHeaders*(url: string, protocol: string = "", customheaders:seq[ tuple[key: string, val: string] ] = @[] ): Future[WebSocket] {.async.} =
  ## Creates a new WebSocket connection,
  ## protocol is optional, "" means no protocol.
  var ws = WebSocket()
  ws.masked = true
  ws.tcpSocket = newAsyncSocket()
  ws.protocol = protocol

  var uri = parseUri(url)
  var port = Port(9001)
  case uri.scheme
    of "wss":
      uri.scheme = "https"
      port = Port(443)
    of "ws":
      uri.scheme = "http"
      port = Port(80)
    else:
      raise newException(WebSocketError,
          &"Scheme {uri.scheme} not supported yet")
  if uri.port.len > 0:
    port = Port(parseInt(uri.port))

  var client = newAsyncHttpClient()

  # Generate secure key.
  var secStr = newString(16)
  for i in 0 ..< secStr.len:
    secStr[i] = char rand(255)
  let secKey = base64.encode(secStr)

  #var ch:seq[ tuple[key: string, val: string] ] = @[ ("Connection", "Upgrade"),
  # ("Upgrade", "websocket"), ("Sec-WebSocket-Version", "13"), ("Sec-WebSocket-Key", secKey) ]
  #ch = concat(customheaders, ch)

  client.headers = newHttpHeaders( 
    @[
    ("Connection", "Upgrade"),
    ("Upgrade", "websocket"),
    ("Sec-WebSocket-Version", "13"),
    ("Sec-WebSocket-Key", secKey) 
    ].concat customheaders )


  if ws.protocol != "":
    client.headers["Sec-WebSocket-Protocol"] = ws.protocol
  var res = await client.get($uri)
  let hasUpgrade = res.headers.getOrDefault("Upgrade")
  if hasUpgrade.toLowerAscii() != "websocket":
    raise newException(WebSocketError,
        &"Failed to Upgrade (Possibly Connected to non-WebSocket url)")
  if ws.protocol != "":
    var resProtocol = res.headers.getOrDefault("Sec-WebSocket-Protocol")
    if ws.protocol != resProtocol:
      raise newException(WebSocketError,
        &"Protocol mismatch (expected: {ws.protocol}, got: {resProtocol})")
  ws.tcpSocket = client.getSocket()

  ws.readyState = Open
  return ws