/*
 * GET users listing.
 */

exports.list = function (req, res) {
    var droplet_collection = global.mongodb.collection('data');
    droplet_collection.find({ creator: 'mango_portal@joowing.com', as: 'task_state_log'  }).limit(113).toArray(function(err, results) {
        res.send(JSON.stringify({ msg: "respond with a resource", data: results, size: results.length }));
    })

};