/**
 * Module dependencies.
 */

var MongoClient = require('mongodb').MongoClient;
var format = require('util').format;

var url = 'mongodb://mongoone.joowing.com:40000,mongotwo.joowing.com:40000,mongothree.joowing.com:40000';
url += '/data_ocean_production_test_env';

var express = require('express');
var routes = require('./routes');
var user = require('./routes/user');
var http = require('http');
var path = require('path');

var app = express();

// all environments
app.set('port', process.env.PORT || 3000);
app.set('views', __dirname + '/views');
app.set('view engine', 'jade');
app.use(express.favicon());
app.use(express.logger('dev'));
app.use(express.bodyParser());
app.use(express.methodOverride());
app.use(express.cookieParser('your secret here'));
app.use(express.session());
app.use(app.router);
app.use(express.static(path.join(__dirname, 'public')));

// development only
if ('development' == app.get('env')) {
    app.use(express.errorHandler());
}

app.get('/', routes.index);
app.get('/users.json', user.list);



MongoClient.connect(url, function (err, db) {
    if (err) throw err;

    global.mongodb = db;
    http.createServer(app).listen(app.get('port'), function () {
        console.log('Express server listening on port ' + app.get('port'));
    });
    http.createServer(app).listen(3001, function () {
            console.log('Express server listening on port ' + app.get('port'));
        });
    http.createServer(app).listen(3002, function () {
            console.log('Express server listening on port ' + app.get('port'));
        });
    http.createServer(app).listen(3003, function () {
            console.log('Express server listening on port ' + app.get('port'));
        });

});