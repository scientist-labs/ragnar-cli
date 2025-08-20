require 'set'

module RubyRag
  module TopicModeling
    class TermExtractor
      # Common English stop words to filter out
      STOP_WORDS = Set.new(%w[
        the be to of and a in that have i it for not on with he as you do at
        this but his by from they we say her she or an will my one all would
        there their what so up out if about who get which go me when make can
        like time no just him know take people into year your good some could
        them see other than then now look only come its over think also back
        after use two how our work first well way even new want because any
        these give day most us is was are been has had were said did get may
      ])
      
      def initialize(stop_words: STOP_WORDS, min_word_length: 3, max_word_length: 20)
        @stop_words = stop_words
        @min_word_length = min_word_length
        @max_word_length = max_word_length
      end
      
      # Extract distinctive terms using c-TF-IDF
      def extract_distinctive_terms(topic_docs:, all_docs:, top_n: 20)
        # Tokenize and count terms in topic
        topic_terms = count_terms(topic_docs)
        
        # Tokenize and count document frequency across all docs
        doc_frequencies = compute_document_frequencies(all_docs)
        
        # Compute c-TF-IDF scores
        scores = {}
        total_docs = all_docs.length.to_f
        
        topic_terms.each do |term, tf|
          # c-TF-IDF formula: tf * log(N / df)
          df = doc_frequencies[term] || 1
          idf = Math.log(total_docs / df)
          scores[term] = tf * idf
        end
        
        # Return top scoring terms
        scores.sort_by { |_, score| -score }
               .first(top_n)
               .map(&:first)
      end
      
      # Standard TF-IDF implementation
      def extract_tfidf_terms(documents:, top_n: 20)
        # Document frequency
        doc_frequencies = compute_document_frequencies(documents)
        total_docs = documents.length.to_f
        
        # Compute TF-IDF for each document
        all_scores = []
        
        documents.each do |doc|
          terms = count_terms([doc])
          doc_length = terms.values.sum.to_f
          
          scores = {}
          terms.each do |term, count|
            tf = count / doc_length  # Normalized term frequency
            df = doc_frequencies[term] || 1
            idf = Math.log(total_docs / df)
            scores[term] = tf * idf
          end
          
          all_scores << scores
        end
        
        # Aggregate scores across all documents
        aggregated = {}
        all_scores.each do |doc_scores|
          doc_scores.each do |term, score|
            aggregated[term] ||= 0
            aggregated[term] += score
          end
        end
        
        # Return top terms
        aggregated.sort_by { |_, score| -score }
                  .first(top_n)
                  .map(&:first)
      end
      
      # Simple term frequency extraction
      def extract_frequent_terms(documents:, top_n: 20)
        terms = count_terms(documents)
        terms.sort_by { |_, count| -count }
             .first(top_n)
             .map(&:first)
      end
      
      private
      
      def tokenize(text)
        # Simple tokenization - can be improved with proper NLP tokenizer
        text.downcase
            .split(/\W+/)
            .select { |word| valid_word?(word) }
      end
      
      def valid_word?(word)
        word.length >= @min_word_length &&
        word.length <= @max_word_length &&
        !@stop_words.include?(word) &&
        !word.match?(/^\d+$/)  # Not pure numbers
      end
      
      def count_terms(documents)
        terms = Hash.new(0)
        
        documents.each do |doc|
          tokenize(doc).each do |word|
            terms[word] += 1
          end
        end
        
        terms
      end
      
      def compute_document_frequencies(documents)
        doc_frequencies = Hash.new(0)
        
        documents.each do |doc|
          # Use set to count each term once per document
          unique_terms = Set.new(tokenize(doc))
          unique_terms.each do |term|
            doc_frequencies[term] += 1
          end
        end
        
        doc_frequencies
      end
      
      # N-gram extraction for phrases
      def extract_ngrams(text, n: 2)
        words = tokenize(text)
        ngrams = []
        
        (0..words.length - n).each do |i|
          ngram = words[i, n].join(" ")
          ngrams << ngram
        end
        
        ngrams
      end
      
      # Extract both unigrams and bigrams
      def extract_mixed_terms(documents:, top_n: 20)
        all_terms = Hash.new(0)
        
        documents.each do |doc|
          # Unigrams
          tokenize(doc).each { |word| all_terms[word] += 1 }
          
          # Bigrams
          extract_ngrams(doc, n: 2).each { |bigram| all_terms[bigram] += 1 }
        end
        
        # Filter and return top terms
        all_terms.select { |term, count| count > 1 }  # Appears more than once
                 .sort_by { |_, count| -count }
                 .first(top_n)
                 .map(&:first)
      end
    end
  end
end