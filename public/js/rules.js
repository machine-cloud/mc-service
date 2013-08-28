$(window).ready(function() {

  var client = new Faye.Client('/faye');

  function rule_add(rule) {
    console.log('rule_add', rule);
    var body = $('table#rules tbody');
    var row = $('<tr id="rule.' + rule._id + '">');
    var condition = [ rule.condition.device, rule.condition.output, rule.condition.compare, rule.condition.value ].join(' ');
    var action = [ rule.action.device, rule.action.input ].join(' ');
    if (rule.action.value) {
      action += (' = ' + rule.action.value);
    }
    row.append('<td>' + condition + '</td>');
    row.append('<td>' + action + '</td>');
    row.append('<td class="nowrap">' +
      // '<a href="/rules/' + rule._id + '/edit" class="btn btn-primary">Edit</a>' +
      // '&nbsp;' +
      '<a href="/rules/' + rule._id + '/delete" class="btn btn-danger">Delete</a>' +
      '</td>');
    body.append(row);
  };

  function rule_remove(rule) {
    console.log('rule_remove', rule);
    $('tr[id="rule.' + rule.id + '"]').remove();
    if (subs[rule.id]) {
      subs[rule.id].cancel();
      delete subs[rule.id]
    }
  }

  function display_io(io) {
    var output = '';
    for (var key in io) {
      output += '<span class="io_key">' + key + '</span><span class="io_type">' + io[key] + '</span>'
    }
    return output;
  }

  client.subscribe('/rule/add', function(rule) {
    rule_add(rule); 
  });

  client.subscribe('/rule/remove', function(rule) {
    rule_remove(rule);
  });

  $.getJSON('/rules.json', function(data) {
    $.each(data, function(rule) {
      rule_add(this);
    });
  });

  $('.timeago').timeago();

});
