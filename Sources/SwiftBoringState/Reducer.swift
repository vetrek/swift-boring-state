//
//  StoreDemo
//

import Observation

/// A protocol that represents a reducer, which is responsible for handling actions
/// and updating the state accordingly. Reducers may also produce side effects.
///
/// - State: The type of state managed by the reducer.
/// - Action: The type of actions that the reducer handles.
public protocol ReducerProtocol {
  associatedtype State
  associatedtype Action
  
  /// Reduces the given state with the specified action and optionally produces an effect.
  ///
  /// - Parameters:
  ///   - state: The current state, which can be modified in place.
  ///   - action: The action to handle.
  /// - Returns: An optional `Effect` that represents any side effects triggered by this action.
  func reduce(state: inout State, action: Action) -> Effect<Action>?
}

/// An extension to the `ReducerProtocol` to allow combining multiple reducers.
public extension ReducerProtocol {
  /// Combines the current reducer with another reducer of the same `State` and `Action` types.
  ///
  /// - Parameter other: Another reducer to combine with.
  /// - Returns: A new reducer that runs both reducers sequentially.
  func combined<Other: ReducerProtocol>(
    with other: Other
  ) -> some ReducerProtocol where Other.State == State, Other.Action == Action {
    CombinedReducer(first: self, second: other)
  }
}

/// A combined reducer that runs two reducers sequentially, combining their side effects.
///
/// - R1: The type of the first reducer.
/// - R2: The type of the second reducer.
public struct CombinedReducer<R1: ReducerProtocol, R2: ReducerProtocol>: ReducerProtocol where R1.State == R2.State, R1.Action == R2.Action {
  public typealias State = R1.State
  public typealias Action = R1.Action
  
  let first: R1
  let second: R2
  
  /// Reduces the state by running both reducers and combining their effects.
  ///
  /// - Parameters:
  ///   - state: The current state, which can be modified in place.
  ///   - action: The action to handle.
  /// - Returns: An optional combined `Effect` from both reducers.
  public func reduce(state: inout State, action: Action) -> Effect<Action>? {
    let effect1 = first.reduce(state: &state, action: action)
    let effect2 = second.reduce(state: &state, action: action)
    return mergeEffects(effect1, effect2)
  }
  
  /// Merges two optional effects into one.
  ///
  /// - Parameters:
  ///   - effect1: The first effect to merge.
  ///   - effect2: The second effect to merge.
  /// - Returns: A merged effect or `nil` if both are `nil`.
  func mergeEffects(_ effect1: Effect<Action>?, _ effect2: Effect<Action>?) -> Effect<Action>? {
    switch (effect1, effect2) {
    case (nil, nil):
      return nil
    case (let e?, nil):
      return e
    case (nil, let e?):
      return e
    case (let e1?, let e2?):
      return Effect.run {
        // Run both effects concurrently
        async let action1 = e1.work()
        async let action2 = e2.work()
        // Collect actions
        let actions = await [action1, action2].compactMap { $0 }
        // Handle actions as needed
        // For simplicity, return the first non-nil action
        return actions.first
      }
    }
  }
}

/// A type-erased reducer.
public struct AnyReducer<Action, State: Sendable>: ReducerProtocol {
  private let _reduce: (inout State, Action) -> Effect<Action>?
  
  /// Initializes an `AnyReducer` with a concrete reducer conforming to `ReducerProtocol`.
  public init<R: ReducerProtocol>(_ reducer: R) where R.State == State, R.Action == Action {
    self._reduce = reducer.reduce
  }
  
  /// Initializes an `AnyReducer` with a closure for the `reduce` function.
  ///
  /// - Parameter reduce: A closure that performs state mutation and returns an optional effect.
  public init(reduce: @escaping (inout State, Action) -> Effect<Action>?) {
    self._reduce = reduce
  }
  
  /// Reduces the state based on the given action.
  public func reduce(state: inout State, action: Action) -> Effect<Action>? {
    _reduce(&state, action)
  }
}
