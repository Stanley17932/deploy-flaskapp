from flask import Flask, request, jsonify
import re
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for Cloud Run"""
    return jsonify({"status": "healthy"}), 200

@app.route('/analyze', methods=['POST'])
def analyze_text():
    """
    Analyze text input and return word count and character count
    
    Expected JSON input:
    {
        "text": "I love cloud engineering!"
    }
    
    Returns:
    {
        "original_text": "I love cloud engineering!",
        "word_count": 4,
        "character_count": 23
    }
    """
    try:
        # Validate request content type
        if not request.is_json:
            return jsonify({"error": "Content-Type must be application/json"}), 400
        
        data = request.get_json()
        
        # Validate required field
        if 'text' not in data:
            return jsonify({"error": "Missing required field: text"}), 400
        
        text = data['text']
        
        # Validate text is a string
        if not isinstance(text, str):
            return jsonify({"error": "Field 'text' must be a string"}), 400
        
        # Perform analysis
        word_count = len(text.split()) if text.strip() else 0
        character_count = len(text)
        
        response = {
            "original_text": text,
            "word_count": word_count,
            "character_count": character_count
        }
        
        logger.info(f"Analyzed text with {word_count} words and {character_count} characters")
        
        return jsonify(response), 200
    
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(405)
def method_not_allowed(error):
    return jsonify({"error": "Method not allowed"}), 405

if __name__ == '__main__':
    import os
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)