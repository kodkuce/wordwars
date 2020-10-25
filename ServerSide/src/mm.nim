{.experimental: "codeReordering".}
import ws, asyncdispatch, asynchttpserver, json, jwt, libsodium/sodium, strutils, tables, sequtils, os

let rheader = newHttpHeaders([("Content-Type","application/json")])
let CONF = parseJson(readFile("../conf.json"))
var lport =CONF["appCONF"]["mm-port"].getInt()
let secret_jwt = CONF["appCONF"]["secret_jwt"].getStr()
let server = newAsyncHttpServer()


var atm_connected_players = 0
var want_to_play:seq[Player]
var in_negotation:seq[ tuple[g,p1,p2,ticks:int, gb,p1b,p2b:bool] ] = @[]

var game_instances : seq[GameInstance]
for i in 0..20:
  game_instances.add( GameInstance(empty:true, status:idling) )


var players: seq[Player]
for i in 0..100:
  players.add(  Player(empty:true))


type
  Player = ref object of RootObj
    empty:bool
    id*:int
    nick*:string
    conn_slot*:int
    conn_ws*:WebSocket

type
  GameState = enum
    idling, negotiating, game_in_progress, offline

type
  GameInstance = ref object of RootObj
    empty:bool
    id*:int
    conn_slot*:int
    conn_ws*:WebSocket
    players_in*:tuple[p1,p2:int]
    status*:GameState
    playing_port*:int
    ip*:string

#proc join_want_to_play(slot:int): Future[tuple[ok: bool, msg: string]] {.async.}=
proc join_want_to_play(slot:int):Future[tuple[ok: bool, msg: string]] {.async.}=
  for p in want_to_play:
    if p.conn_slot == slot:
      return (false,"Player is allready in req queue")
  want_to_play.add(players[slot])
  return (true,"Player added to req queue")

proc unjoin_want_to_play(slot:int):Future[tuple[ok: bool, msg: string]] {.async.}=
    for p in 0..want_to_play.high:
      if want_to_play[p].id == players[slot].id:
        want_to_play.delete(p)
        return (true,"Removed player form req queue")
    return (false,"Player allready is not in queue")

proc send_num_of_players(){.async.}=
  while true:
    for p in players:
      if not p.empty:# and not p.conn_ws.isNil() and p.conn_ws.readyState == Open:
        await p.conn_ws.send( $(%* {"t":"atm_con", "value":atm_connected_players} ) )
    await sleepAsync(2000)

proc init_negotiate_game(){.async.}=
  while true:

    #first we check if we have any free game instance where we can put players
    var free_gi = -1
    for g in 0..game_instances.high: #EMPTY DOSENT MEAN NO PLAYERS, ITS EMPTY_SLOT , like if GI connected
      if game_instances[g].empty == false and game_instances[g].status == idling:
        free_gi = g
        break


    #echo "g:empty ", game_instances[0].empty, " g:status ", game_instances[0].status, " want_to_p: ", want_to_play.high
    #echo game_instances[0].id

    #if we at least have to player who want to play and a free game istance
    if want_to_play.high > 0 and free_gi != -1:

      #mew tuple
      let new_group = (free_gi, want_to_play[0].conn_slot, want_to_play[1].conn_slot, 11, false, false, false)
      in_negotation.add(new_group)

      #send info game instance and players players
      echo "am sending to gi too"
      await game_instances[free_gi].conn_ws.send( $(%* {"t":"confirm_new_game", "players":[ want_to_play[0].id, want_to_play[1].id ] } ), Binary )
      echo "sended to gi too"
      await want_to_play[0].conn_ws.send( $(%* {"t":"confirm_new_game", "game_instance": [ game_instances[free_gi].ip, game_instances[free_gi].playing_port ], "p1":true, "enick":want_to_play[1].nick } ), Binary )
      await want_to_play[1].conn_ws.send( $(%* {"t":"confirm_new_game", "game_instance": [ game_instances[free_gi].ip, game_instances[free_gi].playing_port ], "p1":false, "enick":want_to_play[0].nick } ), Binary )

      #remove players form want to play and change status of game_instance
      want_to_play.delete(0,1)  #so they are not used anymore while they negotiening game

      game_instances[free_gi].status = negotiating

    await sleepAsync(1000)

proc negotiate_game(){.async.}=
  while true:
    for n in in_negotation.high.countdown 0:
      #countdown timer in each negotation
      in_negotation[n][3].dec

      #if 10 seconds passed and did not confirm rollback
      if in_negotation[n][3] < 0:  #in tuple n0 gi, n1 p1, n2 p2, n3 is ticks, 3 bools form confs
        if not game_instances[in_negotation[n][0]].empty:
          echo "send gi comf question"
          await game_instances[in_negotation[n][0]].conn_ws.send( $(%* {"t":"new_game_confirmed", "value":false } ), Binary )
        if not players[in_negotation[n][1]].empty:
          await players[in_negotation[n][1]].conn_ws.send( $(%* {"t":"new_game_confirmed", "value":false } ), Binary )
        if not players[in_negotation[n][2]].empty:
          await players[in_negotation[n][2]].conn_ws.send( $(%* {"t":"new_game_confirmed", "value":false } ), Binary )

        #echo who is not acceptign DEBUG
        echo in_negotation

        #idle back game isntance to be ready to accept other games
        game_instances[in_negotation[n][0]].status = idling

        #add player back to wtp list if he confirmed
        if in_negotation[n][5]: #player 1 did confirm
          want_to_play.insert( players[in_negotation[n][1]] )
          echo "p1 did confirm"
        if in_negotation[n][6]:
          echo "p2 did confirm"
          want_to_play.insert( players[in_negotation[n][2]] )


        # echo(in_negotation[n])
        in_negotation.delete(n) #remove the group
        echo "deleted nego group. fail"


    for n in in_negotation.high.countdown 0:
      if in_negotation[n][4] and in_negotation[n][5] and in_negotation[n][6]: #confirmation bools
        #send info game instance and players players
        if not game_instances[in_negotation[n][0]].empty:
          await game_instances[in_negotation[n][0]].conn_ws.send( $(%* {"t":"new_game_confirmed", "value":true } ) )
        if not players[in_negotation[n][1]].empty:
          await players[in_negotation[n][1]].conn_ws.send( $(%* {"t":"new_game_confirmed", "value":true } ) )
        if not players[in_negotation[n][2]].empty:
          await players[in_negotation[n][2]].conn_ws.send( $(%* {"t":"new_game_confirmed", "value":true } ) )

        game_instances[in_negotation[n][0]].status = game_in_progress
        game_instances[in_negotation[n][0]].players_in = ( players[in_negotation[n][1]].conn_slot, players[in_negotation[n][2]].conn_slot)
        in_negotation.delete(n) #remove the group
        echo "deleted nego group. success"

    await sleepAsync(1000)

proc invalidate_while_playing_game_req(id:int):bool=
  for g in game_instances:
    if g.empty == false and g.status == game_in_progress:
      if g.players_in[0] == id or g.players_in[1] == id:
        return true
  false

proc invalidate_double_connection(ip:bool, id:int):bool=
  result = false
  if ip:
    for p in players:
      if p.id == id:
        result = true
        return
  else:
    for g in game_instances:
      if g.id == id:
        result = true
        return

proc try_find_free_slot(ip:bool):int=
  result = -1
  if ip:
    for p in 0..players.high:
      if players[p].empty:
        players[p].empty = false
        result = p
        return
  else:
    for g in 0..game_instances.high:
      if game_instances[g].empty:
        game_instances[g].empty = false
        result = g
        return

proc clear_slot(ip:bool, slot:int)=
  if ip:
    atm_connected_players.dec
    #if he is requesting game remove him want_to_play group
    for w in 0..want_to_play.high:
      if want_to_play[w].id == players[slot].id:
        want_to_play.delete(w)
        break

    players[slot].empty = true
    players[slot].id = -1
    players[slot].nick = ""
    players[slot].conn_ws = nil
    players[slot].conn_slot = -1
  else:
    game_instances[slot].empty = true
    game_instances[slot].id = -1
    game_instances[slot].conn_slot = -1
    game_instances[slot].conn_ws = nil

proc auth_header( h: HttpHeaders, g:seq[string] ) : (bool, seq[string]) =
  try:
      var gottoken = $h["sec-websocket-protocol",1]

      #gottoken.removePrefix("token ")
      let asJWT = gottoken.toJWT()

      #verify if token is legit
      asJWT.verifyTimeClaims()
      if asJWT.verify(secret_jwt):
        #if is pull needed data
        for toget in g:
          result[1].add($asJWT.claims[toget].node.str)
        result[0] = true
        return

      #can probbaly delete this cuz it would try error if token is bad
      else:
        echo "bad token, this should probbaly newer heppend, need confirm TODO"
        result[0] = false
        result[1].add("Should not heppend check this")
        return

  except JsonParsingError as ex:
    echo "jpe"
    result[0] = false
    result[1].add("Unparsable token")
    return

  except InvalidToken as ex:
    echo "it"
    result[0] = false
    result[1].add(ex.msg)
    return

  except KeyError as ex:
    echo  "ke"
    echo ex.msg
    result[0] = false
    result[1].add("missing authorization token")
    return

  except Exception as ex:
    echo "any"
    echo ex.msg
    result[0] = false
    result[1].add("Something bad is happening, pls report issue to admin")
    return

proc confirm_game_offer(ip:bool,slot:int){.async, gcsafe.} =
  #ip = is player
  if ip: #tuple[g,p1,p2,ticks:int, gb,p1b,p2b:bool
    for n in in_negotation.high.countdown 0:
      if slot == in_negotation[n][1]:
        in_negotation[n][5] = true
        return
      if slot == in_negotation[n][2]:
        in_negotation[n][6] = true
        return
  else:
    echo "grr:", in_negotation[0][0], " slot:", slot
    for n in in_negotation.high.countdown 0:
      if in_negotation[n][0] == slot:
        in_negotation[n][4] = true
        return

proc process_request(req: Request) {.async, gcsafe.} =
  # echo "got request"
  echo "*********************************************************************"
  echo req
  echo "---------------------------------------------------------------------"
  #let rheader = newHttpHeaders([("Content-Type","application/json")])
  var isplayer = false
  var got_slot = -1

  #HERE WE PROCESS GAME INSANCE REPORTING
  if req.url.path == "/games":


    #now first we check if token is legit
    let ok = auth_header(req.headers, @["id","ip","port"])

    try:
      var ws = await newWebSocket(req, "xxx")

      if not ok[0]:
        await ws.send( $(%* {"t":"ConnError", "msg": ok[1]} ), Binary )
        ws.close()
        return

      got_slot = try_find_free_slot(false)
      if got_slot < 0:
        await ws.send( $(%*{"error": [ "Sorry server is full, maybe try leater", ]}), Binary )
        ws.close()
        return


      game_instances[got_slot].empty = false
      game_instances[got_slot].id = parseInt( ok[1][0] )
      game_instances[got_slot].conn_slot = got_slot
      game_instances[got_slot].conn_ws = ws
      game_instances[got_slot].status = offline
      game_instances[got_slot].ip = ok[1][1]
      game_instances[got_slot].playing_port = parseInt( ok[1][2] )

      await ws.send( $(%* {"t":"welcome", "s":got_slot} ), Binary )
      #await ws.send( $(%* {"t":"confirm_new_game", "value":false } ), Binary )

      while ws.readyState == Open:
        let packet = await ws.receivePacket()
        echo "GI: ",packet
        echo game_instances[0].players_in

        try:
          if packet[0] == Binary:
            let jnode = parseJson(packet[1])
            echo jnode

            case jnode["t"].getStr():
              of "status_update":
                if jnode["value"].getStr() == "idling":
                  echo "going idle"
                  game_instances[got_slot].status = idling
                  game_instances[got_slot].players_in = (-1,-1)
                if jnode["value"].getStr() == "game_in_progress":
                  echo "game in progress"
                  game_instances[got_slot].status = game_in_progress
                  game_instances[got_slot].players_in = ( jnode["p_ids"][0].getInt, jnode["p_ids"][1].getInt )


              #accept offerd game
              of "cmf":
                echo "recive cmf from gi"
                await confirm_game_offer(false, got_slot)
              else:
                echo "kill conection i guess"

        except:
          echo "Recived ws msg in invalid format"
          await ws.send( $(%* {"t":"e", "msg": "Recived ws msg in invalid format" } ) )
          ws.close()
          clear_slot(false, got_slot)


    except WebSocketError:
      clear_slot(false, got_slot)
      #echo getCurrentExceptionMsg()
      echo "Websocket connection errored"

  #PLAYER REQUESTS
  elif req.url.path == "/play":
    #echo "dbg: rec reqest on /play"

    #now first we check if token is legit
    let ok = auth_header(req.headers, @["id","nick"])
    if not ok[0]:
      await req.respond(Http403, $(%*{"errors": [ ok[1], ]}), rheader)
      return

    let pid = parseInt( ok[1][0] )
    let pnick = ok[1][1]



    try:
      #now wo try to make connection with ws server :)
      var ws = await newWebSocket(req, "xxx")

       #check if he allready has ws connection
      if invalidate_double_connection(true,pid):
        await ws.send( $(%*{"t":"e", "msg": [ "Double connection is frobiden", ]}), Binary )
        ws.close()
        return

      got_slot = try_find_free_slot(true) #assigne free slot to player
      if got_slot < 0:
        await ws.send( $(%*{"t":"e", "msg": [ "Sorry server is full, maybe try leater", ]}), Binary )
        ws.close()
        return

      #fill player info to its slot
      players[got_slot].id = pid
      players[got_slot].nick = pnick
      players[got_slot].conn_slot = got_slot
      players[got_slot].conn_ws = ws
      players[got_slot].empty = false

      atm_connected_players.inc

      #establised connection first msg :)
      await ws.send( $(%* {"t":"welcome", "nick":pnick } ) )


      while ws.readyState == Open:
        let packet = await ws.receivePacket()
        echo $packet[1]
        if packet[0] == Ping:
          echo "should pong"
        if packet[0] == Pong:
          echo "should chill"


        try:
          if packet[0] == Binary:
            echo "1"
            let jnode = parseJson(packet[1])
            echo "2"
            case jnode["t"].getStr():

              #request game
              of "wtp":
                echo "3"

                if invalidate_while_playing_game_req(pid):
                  await ws.send( $(%* {"t":"ewtp", "msg": "Can not join another game while you allready in one!" } ) )

                elif jnode["value"].getBool():
                  echo "4"
                  let join_ok = await join_want_to_play(got_slot)
                  echo "AA ", join_ok
                  await ws.send( $(%* {"t":"cwtp", "msg": join_ok[1] } ) )
                else:
                  let unjoin_ok = await unjoin_want_to_play(got_slot)
                  await ws.send( $(%* {"t":"ewtp", "msg": unjoin_ok[1] } ) )

              #accept offerd game
              of "cmf":
                #let s = jnode["slot"].getInt
                await confirm_game_offer(true, got_slot)

              else:
                echo "doom"

        except:
          echo "Recived ws msg in invalid format"
          await ws.send( $(%* {"t":"e", "msg": [ "Recived ws msg in invalid format", ] } ) )
          ws.close()




      #clear slot on disconect/ws close
      clear_slot(true, got_slot)
    except WebSocketError as ex:
      # echo "***************************"
      # echo ex.msg
      # echo type(ex.msg)
      # echo type(ex)
      # echo "***************************"

      #echo getCurrentExceptionMsg()
      clear_slot(true, got_slot)
      echo "player websocket closed"
      #probbaly not need it cuz it drops to 404 on fail
      #await req.respond(Http400, $(%*{"error":["Fail to establish websocket connection"]}), rheader)
      return

  #INVALID PATH
  else:
    echo "invalid path"
    await req.respond(Http400, $(%*{"error":["Not Found"]}), rheader)
    return

  # if isplayer:
  #   echo "p dc"
  # else:
  #   echo "gi droped"
  #   game_instances[got_slot].empty = true

asyncCheck send_num_of_players()
asyncCheck init_negotiate_game()
asyncCheck negotiate_game()
waitFor server.serve(Port(lport), process_request)