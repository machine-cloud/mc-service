$(window).ready(function() {

  var client = new Faye.Client('/faye');
  var subs = {}

  function device_add(device) {
    console.log('device_add', device);
    var table = $('.model#model-' + device.model + ' table#devices');
    var tbody = table.find('tbody');
    var row = $('<tr id="device.' + device.id + '">');
    row.append('<td><button class="btn identify" data-id="' + device.id + '">ID</button></td>');
    row.append('<td class="id">' + device.id + '</td>');
    var outputs = $(table).data('outputs').split(',');
    for (var idx in outputs) {
      row.append('<td class="' + outputs[idx] + '"></td>');
    }
    var inputs = $(table).data('inputs').split(',');
    for (var idx in inputs) {
      var type = models[device.model].inputs[inputs[idx]];
      console.log('type', type);
      switch (type) {
        case 'integer':
        case 'float':
          row.append('<td class="led"><input type="text" class="input-small" data-name="' + inputs[idx] + '" data-id="' + device.id + '" name="' + device.id + '-' + inputs[idx] + '" value="000000"></div></td>');
          $(row).find('input').on('change', function() {
            client.publish('/device/' + $(this).data('id').replace('.', '-'), { key:$(this).data('name'), value:$(this).val() });
          });
          break;
        case 'rgb':
          row.append('<td class="led"><input type="text" class="input-small rgb" data-name="' + inputs[idx] + '" data-id="' + device.id + '" name="' + device.id + '-' + inputs[idx] + '" value="000000"></div></td>');
          $(row).find('.rgb').pickAColor();
          $(row).find('.rgb').on('change', function() {
            client.publish('/device/' + $(this).data('id').replace('.', '-'), { key:$(this).data('name'), value:$(this).val() });
          });
          break;
        case 'action':
          row.append('<td class="led"><button data-name="' + inputs[idx] + '" data-id="' + device.id + '" class="btn action">Send</button></td>');
          $(row).find('.action').on('click', function() {
            client.publish('/device/' + $(this).data('id').replace('.','-'), { key:$(this).data('name'), value:'true' });
          });
          break;
      }
    }
    row.append('<td class="timeago time"></td>');
    tbody.append(row);
    $(row).find('.identify').on('click', function() {
      client.publish('/device/' + $(this).data('id').replace('.','-'), { key:'identify', value:'true' });
    });
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

  var models = {};

  $.getJSON('/models.json', function(data) {
    for (var idx in data) {
      var model = data[idx];
      models[model.name] = model;
    }
    $('.model').each(function(idx, model) {
      $.getJSON('/devices/' + $(model).data('name') + '.json', function (devices) {
        $.each(devices, function(idx, device) {
          device_add(device);
        });
      });
    });
  });

  $('.timeago').timeago();

});
