$(window).ready(function() {

  var client = new Faye.Client('/faye');
  var subs = {}

  function device_add(device) {
    console.log('device_add', device);
    var table = $('.model#model-' + device.model + ' table#devices');
    var tbody = table.find('tbody');
    var row = $('<tr id="device.' + device.id + '">');
    row.append('<td class="id">' + device.id + '</td>');
    var outputs = $(table).data('outputs').split(',');
    for (var idx in outputs) {
      row.append('<td class="' + outputs[idx] + '"></td>');
    }
    row.append('<td class="timeago time"></td>');
    tbody.append(row);
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
    var outputs = $(row).parents('table').data('outputs').split(',');
    row.find('.' + message.key).text(message.value);
    row.find('.time').attr('title', (new Date()).toISOString());
    $('.timeago').timeago('updateFromDOM');
  }

  client.subscribe('/device/add', function(device) {
    device_add(device); 
  });

  client.subscribe('/device/remove', function(device) {
    device_remove(device);
  });

  $('.model').each(function(idx, model) {
    $.getJSON('/devices/' + $(model).data('name') + '.json', function (devices) {
      $.each(devices, function(idx, device) {
        device_add(device);
      });
    });
  });

  $('.timeago').timeago();

});
