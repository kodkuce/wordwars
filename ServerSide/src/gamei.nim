{.experimental: "codeReordering".}
import asynchttpserver, asyncdispatch
import libsodium/sodium
import jwt, times, tables
import json, strutils, unicode
import ws, asyncdispatch
import std/monotimes, times, random, json, vmath
import os, asyncnet



type Player = ref object of RootObj
  should_close*:bool
  conn*:WebSocket
  cdr*:float #rocket fire countdown
  accu_power:int #accumulated points for power ups
  accu_fill:seq[int]

type RocketState = enum
  rActive, rGoingDown, rInactive

type Rocket = ref object of RootObj
  state*:RocketState
  pos*:Vec2
  aimx*:float
  word*:string
  owner*:int
  speed*:float
  scrambled*:bool # will just render scrabless client side cuz anyway this game can be easy cheated/boted
  gdowncd*:float

type GameState = enum
  gameSetup, gameWaitingForPlayers, gameStart, gameProcessing, gameEnd, gameCleanup , gameWTF

type Game = ref object of RootObj
  state*:GameState
  wordlist*:seq[string]
  word_n*:int
  rockets*:seq[Rocket]
  players*:seq[Player]
  cdr*:float


let CONF = parseJson(readFile("../conf.json"))
let domain = CONF["appCONF"]["domain"].getStr()
#var mmport:int = CONF["appCONF"]["mm-port"].getInt()
var lport:int = 9011;
var lid:int = 1;
if paramCount() > 1:
  echo "Using passed param for port:", paramStr(1)
  echo "Using passed param as id", paramStr(2)
  try:
    lport = parseInt(paramStr(1))
    lid = parseInt(paramStr(2))
  except:
    echo "Passed params are not a number, quiting app"
    echo "run it like .gamei 7777 2  , first num is port second id"
    quit(1);
else:
  lport = CONF["appCONF"]["gi-port"].getInt()


var secret_jwt = CONF["appCONF"]["secret_jwt"].getStr()
var accepting_ids = [0,0]
randomize()
var tok = create_auth_token()
var lastTick : MonoTime
var server = newAsyncHttpServer()
#Global game obj for easyer access
var game = Game(state:gameSetup)
#game.state = gameSetup
var tomm : WebSocket


proc create_auth_token():string=
  try:
    var atoken = toJWT(%*{
      "header": {
        "alg": "HS256",
        "typ": "JWT"
      },
      "claims": {
        "id": $lid,
        "ip": "0.0.0.0",
        "port": $lport,
        "exp": (getTime() + 1.days).toUnix().int
      }
    })

    atoken.sign(secret_jwt)
    return $atoken
  except:
    echo "MOFO"
    return "mofo"
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
proc sendAll( data:JsonNode ){.async.}=
  for p in game.players:
    if p.conn != nil and p.conn.readyState == Open:
      await safeSend( p.conn, $data )
      # await p.conn.send( $data )

proc safeSend(conn: WebSocket, data: string) {.async.} =
    try:
      #if conn.tcpSocket.
      if game.state in [ gameCleanup, gameWTF, gameEnd ]:
          echo "am returning cuz game ended"
          return
      await conn.send(data)
    except:
      echo "Govno"
      #echo getCurrentExceptionMsg()

proc safeClose( conn:WebSocket ) {.async.} =
  await sleepAsync(10)
  echo "close"



#NETWORK INPUT OUTPUT AS CLIENT FOR MM
proc process_mm_ws(){.async, gcsafe.}=
  while true:
    try:
      #tomm = await newWebSocket("ws://127.0.0.1:9001/games", @["xxx", tok] )
      tomm = await newWebSocket("ws://" & domain & "games", @["xxx", tok] )

      while tomm.readyState == Open:
        var packet = await tomm.receivePacket()

        if packet[0] == Binary:
          let jnode = parseJson(packet[1])

          case jnode["t"].getStr():
            of "welcome":
              echo "READ WELCOME FORM MM"
              if game.state == gameWaitingForPlayers:
                await tomm.send( $(%* {"t":"status_update", "value": "idling" } ), Binary )
              else:
                await tomm.send( $(%* {"t":"status_update", "value": "game_in_progress", "p_ids":accepting_ids } ), Binary )


            of "confirm_new_game":
              accepting_ids[0] = jnode["players"][0].getInt()
              accepting_ids[1] = jnode["players"][1].getInt()
              #auto confirm as soon as you can
              await tomm.send( $(%* {"t":"cmf", "value": true } ), Binary )

            #of "t":"new_game_confirmed", "value":false }

      if tomm.readyState in [Closed, Closing]:
        echo "conn droped"

    except:
      #echo getCurrentExceptionMsg()
      echo "conn to MM serwer lost, trying to recconenct"
      await sleepAsync(1000)

#NETWOKR INPUT OUTPUT AS GAMESERWER
proc process_player_ws(req: Request) {.async, gcsafe.} =

  let ok = auth_header(req.headers, @["id","nick"]) #bool, seq[]
  let id = parseInt(ok[1][0])
  let nick = ok[1][1]
  var took_slot = -1

  if req.url.path == "/ws":

    var new_ws = await newWebSocket(req, "xxx")
    try:

      if not ok[0]:
        await new_ws.send( $(%* {"t":"ConnError", "msg": ok[1]} ), Binary )
        new_ws.close()
        return

      if id notin accepting_ids:
        await new_ws.send( $(%* {"t":"ConnError", "msg": "you are not allowed to access this serwer"} ), Binary )
        new_ws.close()
        return
      #prevent double conneciton
      for i in 0..1:
        if id == accepting_ids[i]:
          if game.players[i].conn == nil :
            game.players[i].conn = new_ws
            took_slot = i
          else:
            await new_ws.send( $(%* {"t":"ConnError", "msg": "double connection? hmm, no!"} ), Binary )
            new_ws.close()
            return

      echo nick, " TS: ", took_slot
      await new_ws.send(  $(%* {"t":"n", "d":"connection established" }), Binary )

      while new_ws.readyState == Open:

        var jRec:JsonNode
        var packet : (Opcode, string)
        try:
          packet = await new_ws.receivePacket()
          # yield packet
          # if packet.failed:
          #   echo "conn closed interupt"
        except:
            echo "coon closed interup of doom"
            game.players[took_slot].conn = nil

        if game.state in [ gameCleanup, gameWTF, gameEnd ]:
          game.players[took_slot].conn = nil
          echo "am returning cuz state change"
          return

        try:
          if packet[0] == Binary:
            jRec = parseJson(packet[1])

            case jRec["t"].getStr():
              #GIKILLROCKET
              of "kr":
                echo "kr: ", jRec
                #check if any rocket has recived word as payload
                if jRec["w"].getStr() != "":
                  for r in 0..game.rockets.len-1:
                    if game.rockets[r].owner != took_slot:
                      if game.rockets[r].state == rActive and game.rockets[r].word == jRec["w"].getStr():
                        #echo "should kill rocket"
                        #found rocket to hack/kill/drop...
                        game.rockets[r].state = rGoingDown
                        game.players[took_slot].accu_power = (game.players[took_slot].accu_power + game.rockets[r].word.len*24).clamp(0,1000)#TODO BACK TO 24
                        await sendAll( (%* {"t":"sd", "i":r } ) )
                        break

              #GIPOWERUP
              of "powerup": #power up , n = 0-scrambler, 1-speed,
                echo "powerup: ", jRec

                if jRec["v"].getInt == 0:
                  if game.players[took_slot].accu_power >= 500:
                    await sendAll( (%* {"t":"powerup_t", "p":took_slot ,"v":475} ) )
                    game.players[took_slot].accu_power += -475
                    game.players[took_slot].accu_fill.add(0)
                    game.players[took_slot].cdr = 0#shoot asap
                elif jRec["v"].getInt == 1:
                  if game.players[took_slot].accu_power >= 1000:
                    await sendAll( (%* {"t":"powerup_t", "p":took_slot ,"v":975} ) )
                    game.players[took_slot].accu_power += -975
                    game.players[took_slot].accu_fill.add(1)
                    game.players[took_slot].cdr = 0


        except JsonParsingError:
          echo "cant parse this json"
          await new_ws.send("""{ t:"n", s:"i", "d":"invalid json fromat in request" }""", Binary)

        except KeyError:
          echo "invalid key recived"
          await new_ws.send("""{ t:"n", s:"i", "d":"invalid key in json request" }""", Binary)

        except WebSocketError:
          echo "Neki ws error"

        except:
          echo getCurrentExceptionMsg()
          echo "Smrt error"


      echo "Connection edned open state"

    except WebSocketError:
      echo "conn droped"
      game.players[took_slot].conn = nil

    except:
      echo "died player ws"




#HANDLE GAME LOGIC
proc mainGameLoop(){.async.}=
  lastTick = getMonoTime()
  while true:

    #calc delta
    let atmTick = getMonoTime()
    let delta = float((atmTick - lastTick).inMilliseconds) / 1000
    lastTick = atmTick

    case game.state:

      #IN THIS STATE WE DO INITIAL GAME SETUP
      of gameSetup:
        #load worldist form data, atm  just manuly
        game.wordlist = @["ACCEPT","ACCIDENT","ACCESS","ABSORB","ABOVE","ABILITY","ACHIEVE","ACTRESS",
        "BARELY","BARRIER","BATHROOM","BEAN","BEAUTIFUL","BELIEVE","BENEATH","BETWEEN","BORROW","BOUNDARY","BUSINESS","BUTTON",
        "CAPITAL","CARRIER","CELEBRITY","CHALLENGE","CHANGE","CHEMICAL","CITIZEN","CLOTHES","CLUSTER","COLLECT","COMFORTABLE"]
        game.wordlist.shuffle()

        #add 2 player slots
        game.players.add( Player( cdr:rand(1.1), accu_fill: @[] ) )
        game.players.add( Player( cdr:rand(1.1), accu_fill: @[] ) )
        game.cdr = 4.0

        #init seq of rockets
        for i in 0..29: #30 rockets is enought i guess
          let r = Rocket(state:rInactive, pos:vec2(9999,9999), scrambled:false, owner: -1)
          game.rockets.add(r)

        #go to next state
        game.state = gameWaitingForPlayers

      #IN THIS STATE WE WAIT FOR PLAYER TO CONNECT SO WE CAN START GAME
      of gameWaitingForPlayers:
        if game.players[0].conn != nil  and  game.players[1].conn != nil:
          game.state = gameStart
        #echo "w8ting for players"
        await sleepAsync(1000)

      #IN THIS STATE WE READY UP AND START GAME
      of gameStart:
        await sendAll( (%* {"t":"gs", "d":"start"} ) ) #type gamestart, data start
        #await sleepAsync(5000)
        echo "Game starts"
        game.state = gameProcessing

      #IN THIS STATE GAME IS PLAYING AND HERE IS BIGEST PART OF GAME LOGIC
      of gameProcessing:

        #SO BASICLY FIRE ROCKETS PART
        for p in 0..1:
          game.players[p].cdr = game.players[p].cdr - delta

          if game.players[p].conn != nil and game.players[p].conn.readyState == Open: #check send
            await game.players[p].conn.send( $(%* {"t":"zz", "v": "0"} ), Binary )

          #if player rockec countdown trigger lounch rocket
          if game.players[p].cdr < 0:

            for r in 0..game.rockets.len-1: #go trough rocket pool and take
              if game.rockets[r].state == rInactive: #first inative rocket

                #set spawn possition and offset for travel
                let rdir:bool = sample( [true, false] )
                game.rockets[r].aimx = if rdir : rand(500.0..750.0) else : rand(150.0..450.0)
                game.rockets[r].pos = if rdir and p==0 : vec2(555,540) elif rdir and p==1 : vec2(555,60)
                                      elif not rdir and p==0 : vec2(469,540) else : vec2(469,60)

                #cycle trough wordlist and get next word
                if game.word_n + 1 > game.wordlist.high:
                  game.word_n = 0
                else :
                  game.word_n.inc()

                game.rockets[r].word = game.wordlist[game.word_n] #set word
                game.rockets[r].owner = p #set owner
                game.rockets[r].gdowncd = 2.0


                game.rockets[r].speed = 30 #set speed
                game.rockets[r].scrambled = false

                #powerups
                echo game.players[p].accu_fill
                if game.players[p].accu_fill.len > 0:
                  if game.players[p].accu_fill[0] == 0: #pw1 scrambler
                    echo " using scrablemr"
                    game.rockets[r].scrambled = true
                  if game.players[p].accu_fill[0] == 1: #pw2 speed
                    echo " using speed boost "
                    game.rockets[r].speed = 70
                  game.players[p].accu_fill.delete(0)

                #change rocket state to active
                game.rockets[r].state = rActive

                #send to palyers info that rocket spawned/lunched
                await sendAll( (%* {"t":"spawn", "i":r, "p": game.rockets[r].pos, "w":game.rockets[r].word, "o":game.rockets[r].owner,
                              "s":game.rockets[r].speed, "c":game.rockets[r].scrambled, "a":game.rockets[r].state.ord}) ) #t:s=spawn, i=id,
                break #loop cuz we spawn only 1 rocket :(

            game.players[p].cdr = rand(3.0) + game.cdr #rest timer for that player for next rocket

        #NOW NEXT THING IS MOVE ROCKETS
        for r in 0..game.rockets.len-1:
          if game.rockets[r].state in [rActive,rGoingDown]:
            #move rocket
            if game.rockets[r].owner == 0 : #rocket is going up to kill P2
              if game.rockets[r].pos.y > 380:  #p1 540start - 160 = 380
                let newdirx = game.rockets[r].aimx - game.rockets[r].pos.x
                let newdiry = abs(newdirx) * -1
                let ndir = vec2(newdirx,newdiry).normalize()
                game.rockets[r].pos = game.rockets[r].pos + ( ndir * delta * game.rockets[r].speed )
              elif game.rockets[r].pos.y < 210: #380 - 170 = 210
                let newdirx = 512 - game.rockets[r].pos.x
                let newdiry = abs(newdirx) * -1
                let ndir = vec2(newdirx,newdiry).normalize()
                game.rockets[r].pos = game.rockets[r].pos + ( ndir * delta * game.rockets[r].speed )
              else:
                game.rockets[r].pos = game.rockets[r].pos + ( vec2(0,-1) * delta * game.rockets[r].speed ) #just go up

              #check if rocket reached ship for KABOOM! endgame
              if game.rockets[r].state == rActive and dist( game.rockets[r].pos, vec2(512,30) ) < 30 :
                echo "P1 won"
                await sendAll( (%* {"t":"ge", "w":0, "i":r} ) )
                game.state = gameEnd
                break

            else: #rocket is going down to kill P1
              if game.rockets[r].pos.y < 220:  #p2 60start + 160 = 220
                let newdirx = game.rockets[r].aimx - game.rockets[r].pos.x
                let newdiry = abs(newdirx)
                let ndir = vec2(newdirx,newdiry).normalize()
                game.rockets[r].pos = game.rockets[r].pos + ( ndir * delta * game.rockets[r].speed )
              elif game.rockets[r].pos.y > 390: #220 + 170
                let newdirx = 512 - game.rockets[r].pos.x
                let newdiry = abs(newdirx)
                let ndir = vec2(newdirx,newdiry).normalize()
                game.rockets[r].pos = game.rockets[r].pos + ( ndir * delta * game.rockets[r].speed )
              else:
                game.rockets[r].pos = game.rockets[r].pos + ( vec2(0,1) * delta * game.rockets[r].speed )

              #check if rocket reached ship for KABOOM! endgame
              if game.rockets[r].state == rActive and dist( game.rockets[r].pos, vec2(512,570) ) < 30 :
                echo "P2 won"
                await sendAll( (%* {"t":"ge", "w":1, "i":r}) )
                game.state = gameEnd
                break


            #for going down rockets/aka diactivated ones we have aprox 1 sec timer before they go to rInactive
            if game.rockets[r].state == rGoingDown:
              game.rockets[r].gdowncd = game.rockets[r].gdowncd - delta
              if game.rockets[r].gdowncd < 0 :
                game.rockets[r].state = rInactive #put rocket to inactive slots now to be reused
                game.rockets[r].pos = vec2( 99999,99999 )


            #send to players info about rocket new pos
            await sendAll(  (%* {"t": "r", "i":r, "p": game.rockets[r].pos})  )

      of gameEnd:

        #close all player connections and null them
        echo "GAME ENDED"
        # game.players[0].conn.readyState = Closed;
        # game.players[1].conn.readyState = Closed;
        game.state = gameCleanup

      of gameCleanup:
        echo "enterd cleanup"
        #kill player connections
        # await sleepAsync(3000)
        # if game.players[0].conn != nil and game.players[0].conn.readyState == Open:
        #   if game.players[0].conn.tcpSocket != nil :
        #     try:
        #       #game.players[0].conn.close()
        #       #if not game.players[0].conn.tcpSocket.isClosed():
        #       echo "closing conn p0"
        #       #game.players[0].conn.readyState = Closed;
        #       game.players[0].conn.readyState = Closing
        #       #game.players[0].conn.hangup()
        #       # game.players[0].conn.tcpSocket.close()
        #       #game.players[0].conn = nil
        #     except:
        #       echo "Failed to close player 0 conn"
        #       echo getCurrentExceptionMsg()

        # if game.players[1].conn != nil and game.players[1].conn.readyState == Open:
        #   if game.players[1].conn.tcpSocket != nil:
        #     try:
        #       #if not game.players[1].conn.tcpSocket.isClosed():
        #       echo "closing conn p1"
        #       #game.players[0].conn.readyState = Closed;
        #       game.players[1].conn.readyState = Closing
        #       #game.players[1].conn.tcpSocket.close()
        #       #game.players[1].conn.hangup()
        #       #game.players[1].conn = nil
        #     except:
        #       echo "Failed to close player 1 conn"
        #       echo getCurrentExceptionMsg()


        #close player connections
        if game.players[0].conn != nil and game.players[0].conn.readyState == Open:
          try:
            game.players[0].conn.close()
            game.players[0].conn = nil
          except:
            echo "WARING failed to close player conn!" #TODO

        if game.players[1].conn != nil and game.players[1].conn.readyState == Open:
          try:
            game.players[1].conn.close()
            game.players[0].conn = nil
          except:
            echo "WARING failed to close player conn!" #TODO


        #set back  cdr to default
        game.cdr = 5.0
        game.players[0].accu_power = 0
        game.players[1].accu_power = 0

        #clean up all rockets
        let offscreen = vec2(9999,9999)
        for r in 0..game.rockets.len-1: #go trough rocket pool and take
          game.rockets[r].state = rInactive
          game.rockets[r].pos = offscreen
          game.rockets[r].scrambled = false
          game.rockets[r].owner = -1
          game.rockets[r].speed = 30


        #tell mm you ready to accept connection again
        await tomm.send(  $(%* { "t":"status_update", "value":"idling" }), Binary )
        game.state = gameWaitingForPlayers
        # game.state = gameWTF
        echo "c4"

      of gameWTF:
        await sleepAsync(2000)
        echo "wtf"

    #run this while loop at some FPS rate
    await sleepAsync(1000/10) #1000/fps


asyncCheck mainGameLoop()
asyncCheck process_mm_ws()
waitfor server.serve(Port(lport), process_player_ws)
# try:
#   #waitfor server.serve(Port(lport), process_player_ws)
#   #echo whygood
#   waitfor server.serve(Port(lport), process_player_ws)

# except:
#   echo "whyYYYYY!"
#   echo getCurrentExceptionMsg();


echo "GAMESERVER CLOSED"

#[
@[]
P1 won
GAME ENDED
enterd cleanup
c4
chaning rS to closing
chaning rS to closeed
closing tcp
Conn is still opend
Why good
Why good
whyYYYYY!
File descriptor not registered.
Async traceback:
  /home/me/Documents/Projects/grammergame/src/gamei.nim(615)                 gamei
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1892)  waitFor
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1582)  poll
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1346)  runOnce
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(210)   processPendingCallbacks
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncmacro.nim(34)       processRequestNimAsyncContinue
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asynchttpserver.nim(279) processRequestIter
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncnet.nim(695)        close
  /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1276)  closeSocket
  #[
    /home/me/Documents/Projects/grammergame/src/gamei.nim(615)                 gamei
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1892)  waitFor
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1582)  poll
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(1346)  runOnce
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncdispatch.nim(210)   processPendingCallbacks
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncmacro.nim(34)       processClientNimAsyncContinue
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asynchttpserver.nim(292) processClientIter
    /home/me/.choosenim/toolchains/nim-1.2.6/lib/pure/asyncfutures.nim(383)    read
  ]#
Exception message: File descriptor not registered.
Exception type:
GAMESERVER CLOSED


SO AROUND 246 i think it excepts there
and i close at 578
]#