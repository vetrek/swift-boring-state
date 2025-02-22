import Observation

// ReadOnlyStore is a simplified, read-only wrapper around Store.
@Observable
@MainActor
public final class ReadOnlyStore<State: Sendable> {
  private var store: Store<State, Never> // Using Never as Action type since it's read-only
  
  public var state: State {
    store.state
  }
  
  public init(initialState: State) {
    // Initialize the internal store with a reducer that can never be called
    self.store = Store(initialState: initialState, reducer: ReducerNever())
  }
  
  // A reducer that is never supposed to reduce actions because actions of type 'Never' cannot exist
  private struct ReducerNever: ReducerProtocol {
    func reduce(state: inout State, action: Never) -> Effect<Never>? {
      // This block will never be executed
    }
  }
  
  /// Creates a new `Store` by scoping down to a `LocalState` at the given key path,
  /// and using a local reducer specific to that sub-state.
  ///
  /// - Parameters:
  ///   - keyPath: A writable key path from this store's `State` to `LocalState`.
  ///   - localReducer: The reducer handling actions for `LocalState`.
  /// - Returns: A `Store` that manages just the scoped sub-state and actions.
  public func shape<LocalReducer: ReducerProtocol>(
    keyPath: WritableKeyPath<State, LocalReducer.State>,
    scopedReducer: LocalReducer
  ) -> Store<LocalReducer.State, LocalReducer.Action> {
    store.shape(keyPath: keyPath, scopedReducer: scopedReducer)
  }
}
