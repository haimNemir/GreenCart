import express, { Request, Response } from 'express'
import { MongoClient, Db } from 'mongodb'

// we can use "Express" only because we have installed it with package.json in Dockerfile.
const app = express() // Here we create an instance of the Express application.
const PORT = parseInt(process.env.PORT || '3000', 10) // process - is a global object in Node.js that provides information about the current running process. The env object of process contains the environment variables of the machine/container and with it we can know the port number on which our image is running. The parseInt(... , 10) is used to convert the string value of the port number to an integer with a base of 10 (decimal). 
const MONGO_URL = process.env.MONGO_URL || 'mongodb://localhost:27017' // Here we define the URL for connecting to MongoDB. The 'mongodb://localhost:27017' - is the default URL for connecting to a local MongoDB instance. the value of MONGO_URL is defined in the docker-compose file as an environment variable and here we use it.
const DB_NAME = 'greencart'

let db: Db 

// the connectDB function creates a connection to the MongoDB database called greencart and stores it in the db variable so the rest of the app can use it
async function connectDB(): Promise<void> {
  const client = new MongoClient(MONGO_URL)
  await client.connect()
  db = client.db(DB_NAME)
  console.log('Connected to MongoDB')
}
// If express receives a GET request to the /health endpoint, it will respond with "OK"/200. 
app.get('/health', (_req: Request, res: Response) => {
  res.status(200).send('OK')
})
// If express receives a GET request to the /api/items endpoint, it will try to fetch all items from the "items" collection (Currently its all the values in the DB) in the MongoDB database and return them as a JSON response. And the Frontend will show for the user only the quantity of the apples. 
app.get('/api/items', async (_req: Request, res: Response) => {
  try {
    const items = await db.collection('items').find({}).toArray()
    res.json(items)
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch items' })
  }
})
// Try to connect to the DB, if succeeds its starts to listen with "Express" on the defined PORT.
connectDB()
  .then(() => {
    app.listen(PORT, () => console.log(`Server listening on port ${PORT}`))
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB:', err)
    process.exit(1)
  })
