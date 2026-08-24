import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
// TODO: Import your environment variable manager (e.g., flutter_dotenv)

class ApiService {
  late final Dio _dio;
  
  // Replace this with your secure env variable, e.g., dotenv.env['OPENROUTER_API_KEY']
  final String _apiKey = 'YOUR_SECURE_API_KEY'; 

  ApiService() {
    // Configure Dio once in the constructor
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://openrouter.ai/api/v1', // Ensure this is 'https://openrouter.ai/api/v1'
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
          HttpHeaders.contentTypeHeader: 'application/json',
          'HTTP-Referer': 'https://your-app.example',
          'X-Title': 'Plant Disease Mobile App',
        },
      ),
    );
  }

  Future<String> encodeImage(File image) async {
    final bytes = await image.readAsBytes();
    return base64Encode(bytes);
  }

  /// Generic method to handle OpenRouter POST requests and response parsing
  Future<String> _postToOpenRouter(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post("/chat/completions", data: data);
      final jsonResponse = response.data;

      if (jsonResponse == null) {
        throw const HttpException('Empty response from OpenRouter');
      }

      if (jsonResponse['error'] != null) {
        throw HttpException(
          jsonResponse['error']['message']?.toString() ?? 'Unknown OpenRouter error',
        );
      }

      final choices = jsonResponse['choices'];
      if (choices == null || choices.isEmpty) {
        throw const HttpException('No response choices returned');
      }

      final content = choices[0]['message']?['content']?.toString();
      if (content == null || content.trim().isEmpty) {
        throw const HttpException('Empty AI response');
      }

      return content.trim();
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error']?['message'] ?? e.message;
      print("DioException: $errorMsg");
      throw Exception('OpenRouter request failed: $errorMsg');
    } catch (e) {
      print("General Exception: $e");
      throw Exception('Error: $e');
    }
  }

  Future<String> sendDiseaseAdvice({
    required String diseaseName,
    String model = "google/gemini-2.5-flash",
  }) async {
    final data = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': "For the plant health condition '$diseaseName', "
              "provide exactly three concise precautionary or management measures. "
              "Each measure must be one short sentence. "
              "Return only three bullet points and no additional explanation.",
        }
      ],
      'max_tokens': 200,
    };

    return _postToOpenRouter(data);
  }

  Future<String> sendImageToOpenRouter({
    required File image,
    int maxTokens = 100,
    String model = "google/gemini-2.5-flash",
  }) async {
    final String base64Image = await encodeImage(image);

    final data = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a plant health image analysis assistant. Your response must be concise.',
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Analyze this image of a plant or leaf. Identify the most likely abnormal condition, '
                  'including plant disease, pest damage, nutrient deficiency, or decay. '
                  'Respond strictly with only the name of the most likely condition. '
                  'Do not provide explanations or additional text. '
                  'If the condition cannot be identified, reply exactly "I don\'t know". '
                  'If the image is not related to a plant, reply exactly "Please pick another image".',
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            },
          ],
        },
      ],
      'max_tokens': maxTokens,
    };

    return _postToOpenRouter(data);
  }

  Future<Map<String, String>> analyzePlantAndGetAdvice({
    required File image,
    String visionModel = "google/gemini-2.5-flash",
    String adviceModel = "google/gemini-2.5-flash",
  }) async {
    final diseaseName = await sendImageToOpenRouter(
      image: image,
      model: visionModel,
    );

    if (diseaseName == "I don't know" || diseaseName == "Please pick another image") {
      return {
        'disease': diseaseName,
        'advice': '',
      };
    }

    final advice = await sendDiseaseAdvice(
      diseaseName: diseaseName,
      model: adviceModel,
    );

    return {
      'disease': diseaseName,
      'advice': advice,
    };
  }
}