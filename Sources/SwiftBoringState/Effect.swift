//
//  StoreDemo
//

/// A structure representing a side effect that produces an action.
///
/// An `Effect` encapsulates asynchronous work that may produce an optional action. It is commonly
/// used to model side effects (e.g., network requests, timers) in unidirectional data flow architectures.
///
/// - Note: `Effect` conforms to `Sendable` so that it can be safely used in concurrent contexts.
/// - Parameter Action: The type of action that may be produced by the effect.
public struct Effect<Action>: Sendable {
  /// The asynchronous work performed by the effect.
  ///
  /// This closure is responsible for executing an asynchronous task and optionally returning an action.
  /// The returned action, if any, can be further dispatched to update the state.
  let work: @Sendable () async -> Action?
  
  /// Creates an effect by specifying the asynchronous work.
  ///
  /// Use this static method to conveniently create an effect from an asynchronous closure.
  ///
  /// - Parameter work: A closure that performs the asynchronous work and returns an optional action.
  /// - Returns: A new `Effect` instance that encapsulates the provided asynchronous work.
  public static func run(_ work: @Sendable @escaping () async -> Action?) -> Effect {
    Effect(work: work)
  }
}

/// Extension to the `Effect` structure for additional functionality.
///
/// This extension provides utility methods to transform the output of an effect.
public extension Effect {
  /// Transforms the action type of the effect.
  ///
  /// This method allows you to map the resulting action from one type to another. It is particularly
  /// useful when you need to adapt effects to match the expected action type in your application's store.
  ///
  /// - Parameter transform: A closure that transforms an action of type `Action` into an action of type `T`.
  /// - Returns: A new `Effect` instance producing an action of type `T`.
  ///
  /// Usage example:
  /// ```swift
  /// let originalEffect: Effect<MyAction> = ...
  /// let transformedEffect = originalEffect.map { myAction in
  ///     // Transform MyAction into AnotherAction.
  ///     AnotherAction(from: myAction)
  /// }
  /// ```
  func map<T>(_ transform: @Sendable @escaping (Action) -> T) -> Effect<T> {
    Effect<T>.run {
      if let result = await self.work() {
        return transform(result)
      }
      return nil
    }
  }
}

/// A type alias representing a reducer function.
///
/// A reducer is a function that takes the current state and an action, modifies the state, and
/// optionally returns an effect to perform side effects. The returned effect may produce further actions
/// that can be handled by the store.
///
/// - Parameters:
///   - Action: The type of action that is processed by the reducer.
///   - State: The type of state that is modified by the reducer.
public typealias Reducer<Action, State> = (inout State, Action) -> Effect<Action>?
