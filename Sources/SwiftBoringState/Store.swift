import Foundation
import SwiftUICore
import Combine
import Observation

/// A type alias for a store specialized with a given reducer.
/// Use this alias to avoid repeating the reducer’s state and action types.
/// - Note: `R` must conform to `ReducerProtocol`.
public typealias StoreOf<R: ReducerProtocol> = Store<R.State, R.Action>

/// A type alias for a read-only store with a specified state type.
public typealias ReadOnlyStoreOf<State: Sendable> = ReadOnlyStore<State>

/// A protocol that abstracts the functionality of a store while erasing its generic type.
/// It provides methods to access the store’s state, send actions, and update the state.
/// - Important: Use this protocol when you need a type-erased store reference.
@MainActor
protocol AnyStoreProtocol {
  /// The current state of the store as a `Sendable` value.
  var state: Sendable { get }
  
  /// Dispatches an action to the store.
  ///
  /// - Parameter action: The action to be handled by the store.
  func send(action: Sendable)
  
  /// Updates the store’s state at the specified key path with a new value.
  ///
  /// - Parameters:
  ///   - keyPath: The key path identifying the portion of the state to update.
  ///   - value: The new value to set at the key path.
  func updateState(keyPath: AnyKeyPath, value: Sendable)
}

/// A class that encapsulates a state management store.
///
/// The `Store` manages state changes and action dispatching using a reducer. It also supports
/// the creation of scoped (child) stores for managing sub-states.
///
/// - Note: The class uses the `@Observable` macro for state observation.
@MainActor
@Observable
public final class Store<State: Sendable, Action: Sendable>: DynamicProperty {
  
  // MARK: - Stored Properties
  
  /// The reducer used to transform the state based on dispatched actions.
  private var reducer: AnyReducer<Action, State>
  
  /// The current state of the store.
  public internal(set) var state: State
  
  /// A published property reflecting the current state; useful for bindings and subscriptions.
  @ObservationIgnored
  @Published public internal(set) var statePublisher: State
  
  /// The key path in the parent store where this store's state is stored.
  @ObservationIgnored
  var parentKeyPath: AnyKeyPath?
  
  /// A type-erased reference to a parent store.
  ///
  /// - Note: This property is used internally when updating the parent's state.
  @ObservationIgnored
  var parentStore: (any AnyStoreProtocol)?
  
  /// The Combine subscription for state updates.
  @ObservationIgnored
  private var subscription: AnyCancellable?
  
  // MARK: - Initialization
  
  /// Creates a new store with an initial state and a reducer.
  ///
  /// - Parameters:
  ///   - initialState: The starting state for the store.
  ///   - reducer: The reducer that defines how state transitions occur.
  ///
  /// The store will use the provided reducer to update its state when actions are dispatched.
  public init<R: ReducerProtocol>(
    initialState: R.State,
    reducer: R
  ) where R.State == State, R.Action == Action {
    self.reducer = AnyReducer(reducer)
    self.state = initialState
    self.statePublisher = initialState
    
    subscription = self.$statePublisher
      .sink { [weak self] state in
        guard let self else { return }
        if let parentStore, let parentKeyPath {
          parentStore.updateState(keyPath: parentKeyPath, value: self.state)
        }
      }
  }
  
  // MARK: - Public Methods
  
  /// Dispatches an action asynchronously to update the store's state.
  ///
  /// - Parameter action: The action to be processed.
  ///
  /// When an action is sent, the store uses its reducer to compute the next state. If the reducer
  /// returns an effect, the effect will be awaited and any resulting action will be sent recursively.
  public func send(action: Action) {
    let effect = reducer.reduce(state: &state, action: action)
    
    // 4) Update statePublisher whenever state changes
    statePublisher = state
    
    guard let effect else { return }
    
    Task { [weak self] in
      guard let self else { return }
      if let newAction = await effect.work() {
        self.send(action: newAction)
      }
    }
  }
  
  /// Dispatches an array of actions asynchronously to update the store's state.
  ///
  /// - Parameter actions: An array of actions to be processed.
  ///
  /// Each action in the array is sent in order using the `send(action:)` method.
  public func send(actions: [Action]) {
    for action in actions {
      send(action: action)
    }
  }
  
  /// Updates a portion of the store's state.
  ///
  /// - Parameters:
  ///   - keyPath: A writable key path indicating the part of the state to update.
  ///   - value: The new value to assign to that part of the state.
  ///
  /// This method updates both the internal state and the published state to ensure that observers
  /// are notified of the change.
  public func update<Value>(
    keyPath: WritableKeyPath<State, Value>,
    value: Value
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.state[keyPath: keyPath] = value
      self.statePublisher = state
    }
  }
  
  /// Creates a scoped child store that manages a subset of the parent's state.
  ///
  /// - Parameters:
  ///   - keyPath: A writable key path from the parent state to the local state.
  ///   - scopedReducer: The reducer that will manage state changes for the scoped (local) state.
  /// - Returns: A new `Store` instance that operates on the local state and actions.
  ///
  /// The child store is connected to its parent so that any changes to the child state are
  /// propagated back to the parent store.
  public func shape<LocalReducer: ReducerProtocol>(
    keyPath: WritableKeyPath<State, LocalReducer.State>,
    scopedReducer: LocalReducer
  ) -> Store<LocalReducer.State, LocalReducer.Action> {
    // Create and return a child Store using the scoped reducer and local state
    let scopedStore = Store<LocalReducer.State, LocalReducer.Action>(
      initialState: state[keyPath: keyPath],
      reducer: scopedReducer
    )
    // Set the parent store and key path
    scopedStore.parentStore = AnyStore<LocalReducer.State>(store: self)
    scopedStore.parentKeyPath = keyPath
    
    return scopedStore
  }
  
}

extension Store {
  /// Updates the store's state at the specified key path with a new value.
  ///
  /// - Parameters:
  ///   - keyPath: A writable key path for a portion of the state.
  ///   - value: The new value to be set at the given key path.
  ///
  /// This method is used internally to synchronize state changes with the published property.
  private func updateState<Value>(keyPath: WritableKeyPath<State, Value>, value: Value) {
    state[keyPath: keyPath] = value
    statePublisher = state
  }
}

/// A type-erased wrapper for a store, preserving a subset of the store’s functionality.
///
/// `AnyStore` allows you to reference a store without exposing its full generic type parameters.
/// It is particularly useful when working with child (scoped) stores.
public struct AnyStore<ScopedState>: AnyStoreProtocol {
  /// A closure that returns the current state.
  private let _state: () -> Sendable
  
  /// A closure that updates the state at a given key path with a new value.
  private let _updateState: (AnyKeyPath, ScopedState) -> Void
  
  /// A closure that sends an action to the store.
  private let _send: (Sendable) -> Void
  
  /// Creates a type-erased store wrapper from a concrete `Store`.
  ///
  /// - Parameter store: The concrete store to be wrapped.
  ///
  /// The generic parameters of the underlying store are captured and erased, allowing the resulting
  /// `AnyStore` to be used without specifying the full store type.
  public init<S: Sendable, A: Sendable>(store: Store<S, A>) {
    _state = { store.state }
    _send = { action in
      if let action = action as? A {
        store.send(action: action)
      }
    }
    _updateState = { keyPath, value in
      // Ensure the keyPath is a WritableKeyPath and the value matches the type
      if let kp = keyPath as? WritableKeyPath<S, ScopedState> {
        store.update(keyPath: kp, value: value)
      }
    }
  }
  
  /// The current state of the wrapped store.
  public var state: Sendable {
    _state()
  }
  
  /// Sends an action to the wrapped store.
  ///
  /// - Parameter action: The action to be dispatched.
  public func send(action: Sendable) {
    _send(action)
  }
  
  /// Updates the state of the wrapped store at the specified key path.
  ///
  /// - Parameters:
  ///   - keyPath: The key path identifying the portion of the state to update.
  ///   - value: The new value to set.
  public func updateState(keyPath: AnyKeyPath, value: ScopedState) {
    _updateState(keyPath, value)
  }
  
  /// An alternate update method that attempts to cast the provided value to the expected type.
  ///
  /// - Parameters:
  ///   - keyPath: The key path identifying the portion of the state to update.
  ///   - value: The new value (as a `Sendable`) to set.
  ///
  /// This method provides additional flexibility when updating state, by attempting to convert
  /// the provided value to the appropriate type.
  func updateState(keyPath: AnyKeyPath, value: Sendable) {
    if let typedValue = value as? ScopedState {
      _updateState(keyPath, typedValue)
    }
  }
}
