$(function() {

  var client = new Faye.Client('/faye');

  client.subscribe('/stats', function(message) {
    $('#messages').text(message["messages"]);
    $('#devices').text(message["devices"]);
  });

  var locations = {
    'sensor.20481': { x: 150, y: 209 },
    'sensor.20482': { x: 473, y: 314 },
    'sensor.20483': { x: 602, y: 272 },
    'sensor.24576': { x: 150, y: 209 },
  };

  var colors = {
    'ok':    { dark: '#479C43', light: '#2EE324' },
    'error': { dark: '#BA4E4E', light: '#F28080' }
  };

  $('#floorplan').drawImage({
    source: 'img/floorplan.png',
    fromCenter: false,
    scale: 1.0,
    load: function() {
      blip_init('sensor.20481');
      blip_init('sensor.20482');
      blip_init('sensor.20483');
    }
  });

  var devices = {};
  var subs = {};
  var states = {};

  $.getJSON('/devices/ENV01.json', function (devices) {
    console.log('devices', devices);
    $.each(devices, function(idx, device) {
      devices[device.id] = device;
      subs[device.id] = client.subscribe('/tick/' + device.id.replace('.', '-'), tick);
      states[device.id] = 'ok';
    });
  });

  var offer = null;

  function tick(message) {
    if (message.key === 'state') {
      states[message.id] = message.value;
    }
    blip_on(message.id);
    if (offer) {
      window.clearTimeout(offer);
      offer = null;
    }
    offer = window.setTimeout(function() {
      blip_off(message.id);
    }, 50);
  }

  function blip_init(id) {
    var state = states[id] || 'ok';
    $('#floorplan').drawEllipse({
      fillStyle: '#03a',
      x: locations[id].x, y: locations[id].y,
      width: 24, height: 24
    });
  }
  function blip_on(id) {
    var state = states[id] || 'ok';
    $('#floorplan').drawEllipse({
      fillStyle: colors[state].light,
      x: locations[id].x, y: locations[id].y,
      width: 18, height: 18
    });
  }

  function blip_off(id) {
    var state = states[id] || 'ok';
    $('#floorplan').drawEllipse({
      fillStyle: colors[state].dark,
      x: locations[id].x, y: locations[id].y,
      width: 18, height: 18
    });
  }
});
