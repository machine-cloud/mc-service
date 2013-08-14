$(window).ready(function() {

  var client = new Faye.Client('/faye');
  var subs = {}

  function device_add(device) {
    console.log('device_add', device);
    var body = $('table#devices tbody');
    var row = $('<tr id="device.' + device.id + '">');
    row.append('<td class="id">' + device.id + '</td>');
    row.append('<td class="timeago time"></td>');
    body.append(row);
    subs[device.id] = client.subscribe('/tick/' + device.id.replace('.', '-'), tick);
  };

  function device_remove(device) {
    console.log('device_remove', device);
    $('tr[id="device.' + device.id + '"]').remove();
    if (subs[device.id]) {
      subs[device.id].cancel();
      delete subs[device.id]
    }
  }

  function tick(message) {
    console.log('tick', message);
    var row = $('tr[id="device.' + message.id + '"]');
    row.find('.time').attr('title', (new Date()).toISOString());
    $('.timeago').timeago('updateFromDOM');
  }

  client.subscribe('/device/add', function(device) {
    device_add(device); 
  });

  client.subscribe('/device/remove', function(device) {
    device_remove(device);
  });

  $.getJSON('/devices.json', function(data) {
    $.each(data, function(device) {
      device_add(this);
    });
  });

  $('.timeago').timeago();

});
