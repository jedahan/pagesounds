geoip = require 'geoip-lite'
util = require 'util'
pcap = require 'pcap'
session = pcap.createSession 'en0', ''
coremidi = require('coremidi')()
osc = require 'osc-min'
dgram = require 'dgram'
socket = dgram.createSocket 'udp4'
request = require 'request'

last_ten_packet_sizes = [0,0,0,0,0,0,0,0,0,0,0]

get_local_address = ->
  os = require "os"
  interfaces = os.networkInterfaces()
  addresses = []
  for k of interfaces
    for k2 of interfaces[k]
      address = interfaces[k][k2]
      addresses.push address.address  if address.family is "IPv4" and not address.internal
  local_address = addresses[0]

get_remote_address = (cb) ->
  if process.env.NODE_ENV is 'development'
    cb '50.75.245.246'
  else
    request 'http://ifconfig.me/ip', (error, response, body) ->
      cb error or body.trim()

# [lat, lon]
# calculation from http://www.movable-type.co.uk/scripts/latlong.html
distance = (ll1, ll2) ->
  return 0 if not ll2 and not ll1
  rad = Math.PI / 180
  R = 6371 # km
  [lat1,lat2,lon1,lon2] = [ll1[0]*rad,ll2[0]*rad,ll1[1]*rad,ll2[1]*rad]
  x = (lon2-lon1) * Math.cos((lat1+lat2)/2)
  y = (lat2-lat1)
  Math.round(Math.sqrt(x*x + y*y) * R)


# send a midi note over osc for some duration
sendnote = (note, duration) ->
  outport = 3333
  buf = osc.toBuffer
    address: "/note"
    args: [ note, 127 ] # note on
  socket.send buf, 0, buf.length, outport, "localhost"
  buf = osc.toBuffer
    address: "/note"
    args: [ note, 0 ] # note off
  setTimeout ->
    socket.send buf, 0, buf.length, outport, "localhost"
  , duration

makesound = (note, duration, instrument=1, volume=1) ->
  # change instrument
  coremidi.write [0xC << 4, instrument, 0]
  # play note
  coremidi.write [144, note, Math.round(127*(.5 + volume/2))]
  # turn off note in a few ms
  setTimeout( (-> coremidi.write([128, note, 0])), duration/100 )

# MAIN
address = local_geo = remote_geo = null

local_address = get_local_address()

get_remote_address (addr) ->
  address = addr
  local_geo = geoip.lookup addr

session.on 'packet', (raw) ->
  if local_geo
    packet = pcap.decode.packet raw

    if packet?.link?.ip?.tcp?.data
      source = packet?.link?.ip?.saddr
      destination = packet?.link?.ip?.daddr
      data = packet?.link?.ip?.tcp?.data?.toString()
      last_ten_packet_sizes.push bytes = packet?.link?.ip?.tcp?.data_bytes
      last_ten_packet_sizes = last_ten_packet_sizes[1..10]

      total_length = packet?.link?.ip?.total_length

      # filter out local to local messages
      [first, local, remote] = (addr.split('.')[0] for addr in [local_address, source, destination])
      unless (first is local) and (first is remote)
        remote_geo = geoip.lookup(if source is address then destination else source)
        if local_geo and remote_geo
          util.print duration = distance(local_geo.ll, remote_geo.ll) / 1000 # km ~= ms # TODO: make it the actual speed of sound or light
          util.print ' '
          remote_addr = if source is address then destination else source
          console.log notes = (Math.round(+dest/2) for dest in remote_addr.split '.')

          for note in notes
            # magic splat! thanks http://coffeescriptcookbook.com/chapters/arrays/max-array-value
            makesound note, duration, 1, bytes/Math.max last_ten_packet_sizes...
          #   sendnote note, duration
