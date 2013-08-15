$(window).ready(function() {

  var client = new Faye.Client('/faye');

  function model_add(model) {
    console.log('model_add', model);
    var body = $('table#models tbody');
    var row = $('<tr id="model.' + model._id + '">');
    row.append('<td>' + model.name + '</td>');
    row.append('<td>' + display_io(model.inputs) + '</td>');
    row.append('<td>' + display_io(model.outputs) + '</td>');
    row.append('<td class="nowrap">' +
      '<a href="/models/' + model._id + '/edit" class="btn btn-primary">Edit</a>' +
      '&nbsp;' +
      '<a href="/models/' + model._id + '/delete" class="btn btn-danger">Delete</a>' +
      '</td>');
    body.append(row);
  };

  function model_remove(model) {
    console.log('model_remove', model);
    $('tr[id="model.' + model.id + '"]').remove();
    if (subs[model.id]) {
      subs[model.id].cancel();
      delete subs[model.id]
    }
  }

  function display_io(io) {
    var output = '';
    for (var key in io) {
      output += '<span class="io_key">' + key + '</span><span class="io_type">' + io[key] + '</span>'
    }
    return output;
  }

  client.subscribe('/model/add', function(model) {
    model_add(model); 
  });

  client.subscribe('/model/remove', function(model) {
    model_remove(model);
  });

  $.getJSON('/models.json', function(data) {
    $.each(data, function(model) {
      model_add(this);
    });
  });

  $('.timeago').timeago();

});
