geoip = require 'geoip-lite'
util = require 'util'
pcap = require 'pcap'
session = pcap.createSession 'en0', ''
coremidi = require('coremidi')()
osc = require 'osc-min'
dgram = require 'dgram'
socket = dgram.createSocket 'udp4'
request = require 'request'

local_address = local_geo = address = remote_geo = 0

os = require "os"
interfaces = os.networkInterfaces()
addresses = []
for k of interfaces
  for k2 of interfaces[k]
    address = interfaces[k][k2]
    addresses.push address.address  if address.family is "IPv4" and not address.internal
local_address = addresses[0]

###
request 'http://ifconfig.me/ip', (error, response, body) ->
  if error
    console.error error
  address = body.trim()

  local_geo = geoip.lookup address
  console.log address, local_geo.ll
###
address = '50.75.245.246'
local_geo = geoip.lookup address

session.on 'packet', (raw) ->
  if local_geo
    packet = pcap.decode.packet raw

    if packet?.link?.ip?.tcp?.data
      source = packet?.link?.ip?.saddr
      destination = packet?.link?.ip?.daddr
      data = packet?.link?.ip?.tcp?.data?.toString()
      bytes = packet?.link?.ip?.tcp?.data_bytes
      total_length = packet?.link?.ip?.total_length

      # filter out local to local messages
      [first, local, remote] = (addr.split('.')[0] for addr in [local_address, source, destination])
      unless (first is local) and (first is remote)
        remote_geo = geoip.lookup(if source is address then destination else source)
        if local_geo and remote_geo
          duration = distance(local_geo.ll, remote_geo.ll) / 1000 # km ~= ms # TODO: make it the actual speed of sound or light
          for dest in destination.split '.'
            note = +dest / 2
            makesound note, duration
            sendnote note, duration

# [lat, lon]
# calculation from http://www.movable-type.co.uk/scripts/latlong.html
distance = (ll1, ll2) ->
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

makesound = (note, duration) ->
    coremidi.write [0xC << 4, 14, 0]
    coremidi.write [144, note, 127]
    setTimeout( (-> coremidi.write([128, note, 0])), duration/100 )