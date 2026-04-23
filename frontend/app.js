// Because app.js is included in index.html, it will run as soon as the page loads. And this block of fetch will run immediately even its not inside a function.
fetch('/api/items') //Return all the values from the DB as a "Promise", meaning "I'm working on it, I'll let you know when I'm done."
  .then(function(res) { return res.json() }) // Only after the fetch is complete, the "then" block will run, and the "res.json()" will parse the response "The row data" into a JavaScript object.
  .then(function(items) { // Only after the parsing is complete, this "then" block will run, and the "items" variable will contain the result from the parsing.
    var apples = items.find(function(item) { return item.name === 'apples' }) // Find the first value that calls "apples" in the "name" column.
    document.getElementById('apple-count').textContent = apples ? apples.qty : 'Not found' // Find the element with the id "apple-count" in the index.html, and set its text content to the value of the "qty" column for the "apples" row. 
  })
  .catch(function() {
    document.getElementById('apple-count').textContent = 'Error loading data'
  })
