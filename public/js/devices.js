$(window).ready(function() {

  function device_add(device) {
    var table = $('table#devices');
    var row = $('<tr id="device.' + device.id + '">');
    row.append('<td class="id">' + device.id + '</td>');
    row.append('<td class="timeago time"></td>');
    table.append(row);
  };

  function device_remove(device) {
    $('tr[id="device.' + device.id + '"]').remove();
  }

  function tick(message) {
    var row = $('tr[id="device.' + message.id + '"]');
    row.find('.time').attr('title', (new Date()).toISOString());
    $('.timeago').timeago('updateFromDOM');
  }

  var client = new Faye.Client('/faye');

  client.subscribe('/devices/add', function(device) {
    device_add(device); 
  });

  client.subscribe('/devices/remove', function(device) {
    device_remove(device);
  });

  client.subscribe('/ticks', function(message) {
    tick(message);
  });

  $('.timeago').timeago();

});
