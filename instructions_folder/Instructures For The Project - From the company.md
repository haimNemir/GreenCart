This file, “Instructures For The Project - From the company”, is the original template of the project on which everything is built. The “Source Of Truth - Architecture decisions” file was created based on it, in order to detail the action plan and define the correct architecture.

Instructions:
1.	You need to provision a new Web application
2.	This is a simple “hello world” with a little apples page
3.	The architecture should include : NodeJS, MongoDB, Containers.
4.	The runtime should be on any Linux distro you prefer
5.	Every component of the architecture should run in its own container
6.	All the architecture should be fully defined by scripts and code (IaC) saved in github
7.	The DB should contain this data: [ 
    { "_id": 1, "name": "apples", "qty": 5, "rating": 3 }, 
    { "_id": 2, "name": "bananas", "qty": 7, "rating": 1, "microsieverts": 0.1 },
    { "_id": 3, "name": "oranges", "qty": 6, "rating": 2 },
    { "_id": 4, "name": "avocados", "qty": 3, "rating": 5 }, 
    ]
8.	The exercise submission should be a git repo with all the scripts and automation code to provision the architecture.
9.	The exercise will be checked by running the scripts in the submitted repo.
10.	Tests that the exercise should pass:
•	Provision from scratch of the entire architecture
•	The html page returns the number of apples in the DB
•	Visual demonstartion of the architecure (containers, netwrok topology etc..)
11.	Bonus:
•	Full ci/cd pipeline with one of the cloud providers
•	Readme page in the git repo with guid that explains about the app, architecture design etc..
•	Load balancer
•	Your own ideas will be welcome - create a PULL REQUEST to this branch
12.	At the end of the exercise you will be asked about the architecture design and the components to demonstrate your ability to learn and understand new areas and technology.
 
