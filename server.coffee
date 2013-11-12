geoip = require 'geoip-lite'
util = require 'util'
pcap = require 'pcap'
session = pcap.createSession 'en0', ''
coremidi = require('coremidi')()

geo = geoip.lookup '184.74.199.219'

session.on 'packet', (raw) ->
    packet = pcap.decode.packet raw
    source = packet?.link?.ip?.saddr
    destination = packet?.link?.ip?.daddr
    data = packet?.link?.ip?.tcp?.data?.toString()
    host = /Host: (.*)/.exec(data)?[1]

    if host? and /192.168.1.*/.test source
        geo2 = geoip.lookup destination
        d = distance geo.ll, geo2.ll
        console.log "#{d}km apart"
        console.log "#{source} -> #{host}"
        for dest in destination.split '.'
            note = +dest / 2
            coremidi.write [144, note, 127]
            setTimeout( (-> coremidi.write([128, note, 0])), d )

# [lat, lon]
# calculation from http://www.movable-type.co.uk/scripts/latlong.html
distance = (ll1, ll2) ->
    rad = Math.PI / 180
    R = 6371 # km
    [lat1,lat2,lon1,lon2] = [ll1[0]*rad,ll2[0]*rad,ll1[1]*rad,ll2[1]*rad]
    x = (lon2-lon1) * Math.cos((lat1+lat2)/2)
    y = (lat2-lat1)
    Math.round(Math.sqrt(x*x + y*y) * R)