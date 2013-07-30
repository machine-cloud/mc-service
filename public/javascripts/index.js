$(function() {

  var client = new Faye.Client('/faye');

  client.disable('websocket');

  client.subscribe('/stats', function(message) {
    $('#messages').text(message["message.rate"]);
    $('#clients').text(message["client.count"]);
  });

});
