# Step 1: Use an official lightweight Python runtime as a parent image
FROM python:3.11-slim

# Step 2: Set the working directory inside the container
WORKDIR /app

# Step 3: Copy the requirements file into the container at /app
COPY requirements.txt .

# Step 4: Install the Python dependencies listed in requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# Step 5: Copy the rest of the application code into the container
COPY app.py .

# Step 6: Expose the port that the Flask app runs on
EXPOSE 5001

# Step 7: Define the command to run the application when the container starts
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "--threads", "4", "app:app"]





# BREAKLDOWN
# FROM python:3.12-slim
# "Get me a computer with Python already installed" (slim = smaller/lighter version)

# WORKDIR /app
# "Create a folder called /app and work inside it"

# COPY requirements.txt .
# "Copy my requirements.txt file into the container first"

# RUN pip install --no-cache-dir -r requirements.txt
# "Install all dependencies from requirements.txt, but don't save any leftover junk files"

# COPY app.py .
# "Now copy my actual app code into the container"

# EXPOSE 5001
# "My app listens on port 5001, just so you know"

# CMD ["python", "app.py"]
# "When the container starts, run the app"