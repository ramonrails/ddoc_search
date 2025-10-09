# frozen_string_literal: true

# CircuitBreaker module provides a wrapper around Circuitbox to implement
# circuit breaker pattern for external service calls.
# This helps prevent cascading failures when downstream services are slow or failing.
module CircuitBreaker
  # Executes a block of code with circuit breaker protection
  # @param service_name [String] unique identifier for the service being called
  # @yield [void] the block of code to execute with circuit breaker protection
  # @return [Object] result of the executed block
  def self.call(service_name, &block)
    # Configure circuit breaker settings for the specified service
    # - exceptions: list of exceptions that should trigger the circuit breaker
    # - timeout_seconds: time in seconds after which a call is considered failed
    # - sleep_window: time in seconds to wait before attempting to reset the circuit
    # - volume_threshold: minimum number of calls required before the circuit breaker starts tracking failures
    # - error_threshold: percentage of failed calls that will trigger the circuit breaker
    circuit = Circuitbox.circuit(service_name, {
      exceptions: [ Elasticsearch::Transport::Transport::Error, Redis::BaseError ],
      timeout_seconds: 5,
      sleep_window: 30,
      volume_threshold: 5,
      error_threshold: 50
    })

    # Execute the provided block with circuit breaker protection
    # This will automatically handle opening/closing the circuit based on failure rates
    circuit.run(&block)
  end
end
