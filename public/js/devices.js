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
    var inputs = $(table).data('inputs').split(',');
    for (var idx in inputs) {
      row.append('<td class="led"><input type="text" class="input-small rgb" data-id="' + device.id + '" name="' + device.id + '-led" value="000000"></div></td>');
    }
    $('.rgb').pickAColor();
    $('.rgb').on('change', function(foo, bar) {
      var val = $(this).val();
      var r = (parseInt(val.slice(0, 2), 16) / 255).toFixed(2);
      var g = (parseInt(val.slice(2, 4), 16) / 255).toFixed(2);
      var b = (parseInt(val.slice(4, 6), 16) / 255).toFixed(2);
      for (var i=0; i<3; i++) {
        var input = $(this);
        setTimeout(function() {
          client.publish('/device/' + input.data('id').replace('.', '-'), { key:"led", value:[r,g,b].join(',') });
        }, i*100);
      }
    });
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
    //console.log('tick', message);
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
