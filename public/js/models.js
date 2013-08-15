$(window).ready(function() {

  var client = new Faye.Client('/faye');

  function model_add(model) {
    console.log('model_add', model);
    var body = $('table#models tbody');
    var row = $('<tr id="model.' + model.id + '">');
    row.append('<td>' + model.name + '</td>');
    row.append('<td>' + model.inputs + '</td>');
    row.append('<td>' + model.outputs + '</td>');
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

  function tick(message) {
    console.log('tick', message);
    var row = $('tr[id="model.' + message.id + '"]');
    row.find('.time').attr('title', (new Date()).toISOString());
    $('.timeago').timeago('updateFromDOM');
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
