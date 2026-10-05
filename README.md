# StudySense
AI-powered study system to help students study using their own course materials. System will focus on identifying a student's weak areas and create personalized study sessions. 

Students will be able to upload notes, PDFs, lecture materials and other study documents. The AI will use the materials to answer questions and create study materials including flashcards.

Main features:
upload course notes and files
ask the AI questions about the materials
generate flashcards
generate practice questions
complete personalized study sessions
save previous study sessions
track areas they are struggling
receive study recommendations based on performance

Data:
The prototype uses Ai generated Biology and Psychology documents as sample data to allow the data processing and AI portions of the project to be tested before using actual student uploaded materials. Python and Owen will be used to create flashcards and answer questions the student may have.

Data Cleaning:

The data for this project consists of study materials that are collected for use in the StudySense application. The materials can come from TXT, PDF, and DOCX files uploaded by the user, as well as notes entered directly into the application.
The original uploaded files are stored in the data/raw directory. The extracted and cleaned versions of the materials are stored in the data/cleaned directory. The cleaned text is also stored in the application's studyData.json file so that it can be reused by the study features.
The cleaning process extracts text from the uploaded files and removes unnecessary formatting and other material that is not useful for studying. The cleaned text is then used by StudySense for features such as asking questions about the material and generating flashcards.
The size of the dataset will depend on the study materials collected. The initial dataset contains the study files currently being used to test the application. Additional study materials can be added as the project develops.


Workflow:
Students will upload their study materials. The system will process and clean the files and make the information available to the AI. Students can then ask questions or begin a study session.
During a study session, the system can generate flashcards and practice questions. The student's answers can be used to determine which topics they understand and which topics they are struggling with. The system can then use this information to create future study sessions focused on the student's weak areas.

Future Goal:
The long-term goal is to create a personalized AI tutor that does more than simply answer questions. The system should understand the student's course materials, track their study progress, identify weaknesses, and continuously adjust their study sessions to help them improve.
