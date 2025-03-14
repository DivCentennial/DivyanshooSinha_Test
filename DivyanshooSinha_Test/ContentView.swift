import SwiftUI
import Combine

// MARK: - Models

// Updated model structure to match v2 API response
struct TriviaQuestion: Identifiable, Decodable {
    let id: String
    let category: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    let question: Question
    let difficulty: String
    
    struct Question: Decodable {
        let text: String
    }
}

enum TriviaError: Error {
    case networkError
    case decodingError
    case invalidResponse
}

enum Difficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
    
    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }
}

// MARK: - View Models

class TriviaViewModel: ObservableObject {
    @Published var questions: [TriviaQuestion] = []
    @Published var currentQuestionIndex = 0
    @Published var shuffledAnswers: [String] = []
    @Published var selectedAnswer: String?
    @Published var timeRemaining: Double = 10.0
    @Published var showHint = false
    @Published var isAnswered = false
    @Published var score = 0
    @Published var isGameOver = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var timer: AnyCancellable?
    private var transitionTimer: AnyCancellable?
    
    let questionCount = 6
    
    // API key should be added here securely in a real app
    private let apiKey = "YOUR_API_KEY_HERE" // Replace this with your actual API key
    
    func fetchQuestions(difficulty: Difficulty) {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "https://the-trivia-api.com/v2/questions?limit=\(questionCount)&difficulty=\(difficulty.rawValue)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "3KmksCYspWRErAe4u4DDffypc")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    print("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                // Print the response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("API Response: \(jsonString)")
                }
                
                do {
                    let decodedResponse = try JSONDecoder().decode([TriviaQuestion].self, from: data)
                    self.questions = decodedResponse
                    if !self.questions.isEmpty {
                        self.prepareQuestion()
                    } else {
                        self.errorMessage = "No questions returned"
                    }
                } catch {
                    print("Decoding error: \(error)")
                    self.errorMessage = "Could not decode response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func prepareQuestion() {
        guard currentQuestionIndex < questions.count else {
            isGameOver = true
            return
        }
        
        let question = questions[currentQuestionIndex]
        var answers = question.incorrectAnswers
        answers.append(question.correctAnswer)
        shuffledAnswers = answers.shuffled()
        
        // Reset for new question
        selectedAnswer = nil
        isAnswered = false
        showHint = false
        timeRemaining = 10.0
        
        // Start timer
        startTimer()
    }
    
    func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.timeRemaining > 0 && !self.isAnswered {
                    self.timeRemaining -= 0.1
                    if self.timeRemaining <= 0 {
                        self.timeRemaining = 0
                        self.timeExpired()
                    }
                }
            }
    }
    
    func selectAnswer(_ answer: String) {
        guard !isAnswered else { return }
        
        selectedAnswer = answer
        isAnswered = true
        
        if answer == questions[currentQuestionIndex].correctAnswer {
            score += 1
        }
        
        // Stop the timer
        timer?.cancel()
        
        // Set up transition to next question
        transitionToNextQuestion()
    }
    
    func timeExpired() {
        isAnswered = true
        
        // Set up transition to next question
        transitionToNextQuestion()
    }
    
    func transitionToNextQuestion() {
        transitionTimer?.cancel()
        transitionTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.transitionTimer?.cancel()
                self.currentQuestionIndex += 1
                
                if self.currentQuestionIndex < self.questions.count {
                    self.prepareQuestion()
                } else {
                    self.isGameOver = true
                }
            }
    }
    
    func showHintAction() {
        guard !showHint && !isAnswered else { return }
        
        showHint = true
    }
    
    func resetGame() {
        questions = []
        currentQuestionIndex = 0
        score = 0
        isGameOver = false
        isAnswered = false
        timer?.cancel()
        transitionTimer?.cancel()
    }
    
    func getScorePercentage() -> Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(score) / Double(questions.count)) * 100)
    }
    
    // Returns icon name based on category
    func getCategoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case let s where s.contains("science"):
            return "flask.fill"
        case let s where s.contains("history"):
            return "book.fill"
        case let s where s.contains("geography"):
            return "globe"
        case let s where s.contains("music"):
            return "music.note"
        case let s where s.contains("sport"):
            return "sportscourt.fill"
        case let s where s.contains("film") || s.contains("movie"):
            return "film.fill"
        case let s where s.contains("food"):
            return "fork.knife"
        case let s where s.contains("art"):
            return "paintpalette.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var viewModel = TriviaViewModel()
    @State private var selectedDifficulty = Difficulty.medium
    @State private var showingGame = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Trivia Challenge")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Picker("Difficulty", selection: $selectedDifficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.displayName).tag(difficulty)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                Button {
                    viewModel.resetGame()
                    viewModel.fetchQuestions(difficulty: selectedDifficulty)
                    showingGame = true
                } label: {
                    Text("Play Game")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .navigationBarTitle("Trivia Game", displayMode: .inline)
            .fullScreenCover(isPresented: $showingGame) {
                GameView(viewModel: viewModel, isPresented: $showingGame)
            }
        }
    }
}

struct ErrorView: View {
    let errorMessage: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(errorMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            
            Button {
                isPresented = false
            } label: {
                Text("Return to Main Menu")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct GameView: View {
    @ObservedObject var viewModel: TriviaViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        if viewModel.isLoading {
            LoadingView()
        } else if let errorMessage = viewModel.errorMessage {
            ErrorView(errorMessage: errorMessage, isPresented: $isPresented)
        } else if viewModel.isGameOver {
            GameOverView(score: viewModel.getScorePercentage(), isPresented: $isPresented)
        } else if !viewModel.questions.isEmpty {
            QuestionView(viewModel: viewModel)
        } else {
            Text("No questions available")
                .font(.title)
                .padding()
        }
    }
}

struct QuestionView: View {
    @ObservedObject var viewModel: TriviaViewModel
    
    var currentQuestion: TriviaQuestion {
        viewModel.questions[viewModel.currentQuestionIndex]
    }
    
    // Used for flashing timer
    private var shouldFlashTimer: Bool {
        viewModel.timeRemaining <= 3.0 && Int(viewModel.timeRemaining * 2) % 2 == 0
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress and timer
            HStack {
                Text("Question \(viewModel.currentQuestionIndex + 1)/\(viewModel.questionCount)")
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    Text(String(format: "%.1f", viewModel.timeRemaining))
                        .foregroundColor(shouldFlashTimer ? .red : .primary)
                        .font(.system(size: 18, weight: .bold))
                    
                    Image(systemName: "clock")
                        .foregroundColor(shouldFlashTimer ? .red : .primary)
                }
            }
            .padding(.horizontal)
            
            // Timer progress bar
            ProgressView(value: viewModel.timeRemaining, total: 10)
                .progressViewStyle(LinearProgressViewStyle(tint: viewModel.timeRemaining <= 3 ? .red : .blue))
                .animation(.linear, value: viewModel.timeRemaining)
                .padding(.horizontal)
            
            // Category
            HStack {
                Image(systemName: viewModel.getCategoryIcon(for: currentQuestion.category))
                    .font(.title)
                
                Text(currentQuestion.category)
                    .font(.headline)
            }
            .padding(.top)
            
            // Question - Updated to use question.text
            ScrollView {
                Text(currentQuestion.question.text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(height: 100)
            
            // Answer options
            VStack(spacing: 10) {
                ForEach(viewModel.shuffledAnswers, id: \.self) { answer in
                    AnswerButton(
                        answer: answer,
                        isSelected: viewModel.selectedAnswer == answer,
                        isCorrect: answer == currentQuestion.correctAnswer,
                        isAnswered: viewModel.isAnswered,
                        showHint: viewModel.showHint && answer != currentQuestion.correctAnswer &&
                                 !viewModel.shuffledAnswers.prefix(2).contains(answer),
                        action: {
                            viewModel.selectAnswer(answer)
                        }
                    )
                }
            }
            .padding(.horizontal)
            
            // Hint button
            Button {
                viewModel.showHintAction()
            } label: {
                Text("Hint")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.showHint || viewModel.isAnswered ? Color.gray : Color.orange)
                    .cornerRadius(10)
            }
            .disabled(viewModel.showHint || viewModel.isAnswered)
            .padding(.horizontal)
            .padding(.top)
            
            Spacer()
        }
        .padding()
        .navigationBarTitle("Trivia Game", displayMode: .inline)
    }
}

struct AnswerButton: View {
    let answer: String
    let isSelected: Bool
    let isCorrect: Bool
    let isAnswered: Bool
    let showHint: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(answer)
                    .font(.headline)
                    .foregroundColor(foregroundColor)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if isAnswered {
                    Image(systemName: indicatorIcon)
                        .foregroundColor(indicatorColor)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(10)
        }
        .disabled(isAnswered || showHint)
        .opacity(showHint ? 0.3 : 1.0)
        .animation(.easeInOut, value: showHint)
        .animation(.easeInOut, value: isAnswered)
    }
    
    private var backgroundColor: Color {
            if isAnswered {
                if isCorrect {
                    return Color.green.opacity(0.3)
                } else if isSelected {
                    return Color.red.opacity(0.3)
                } else {
                    return Color.gray.opacity(0.3)
                }
            } else {
                return isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.1)
            }
        }
        
        private var foregroundColor: Color {
            if isAnswered && !isCorrect && !isSelected {
                return .gray
            } else {
                return .primary
            }
        }
        
        private var indicatorIcon: String {
            if isCorrect {
                return "checkmark.circle.fill"
            } else if isSelected {
                return "xmark.circle.fill"
            } else {
                return ""
            }
        }
        
        private var indicatorColor: Color {
            isCorrect ? .green : .red
        }
    }

    struct GameOverView: View {
        let score: Int
        @Binding var isPresented: Bool
        
        var body: some View {
            VStack(spacing: 30) {
                Text("Game Over!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("You scored \(score)%")
                    .font(.title)
                
                Button {
                    isPresented = false
                } label: {
                    Text("Return to Main Menu")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    struct LoadingView: View {
        var body: some View {
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(2)
                
                Text("Loading questions...")
                    .font(.headline)
                    .padding(.top, 30)
            }
        }
    }

    #Preview {
        ContentView()
    }
