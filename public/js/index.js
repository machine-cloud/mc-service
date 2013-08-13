$(function() {

  var client = new Faye.Client('/faye');

  client.subscribe('/stats', function(message) {
    $('#messages').text(message["messages"]);
    $('#devices').text(message["devices"]);
  });

});
