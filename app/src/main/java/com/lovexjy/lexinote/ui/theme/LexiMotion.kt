package com.lovexjy.lexinote.ui.theme

import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.TweenSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/**
 * Shared motion tokens and reusable tactile/transition helpers for LexiNote Android.
 */
object LexiMotion {
    const val DurMicro = 100
    const val DurFast = 160
    const val DurBase = 220
    const val DurSlow = 300
    const val DurStaggerStep = 30
    const val StaggerMaxItems = 8

    val EaseOut = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
    val EaseInOut = CubicBezierEasing(0.65f, 0f, 0.35f, 1f)
    val EaseDrawer = CubicBezierEasing(0.32f, 0.72f, 0f, 1f)

    fun <T> uiSpring(): SpringSpec<T> = spring(
        dampingRatio = 0.86f,
        stiffness = 380f
    )

    fun <T> fastTween(reduced: Boolean = false): TweenSpec<T> = tween(
        durationMillis = if (reduced) 0 else DurFast,
        easing = EaseOut
    )

    fun <T> baseTween(reduced: Boolean = false): TweenSpec<T> = tween(
        durationMillis = if (reduced) 0 else DurBase,
        easing = EaseOut
    )

    fun <T> microTween(reduced: Boolean = false): TweenSpec<T> = tween(
        durationMillis = if (reduced) 0 else DurMicro,
        easing = EaseOut
    )

    fun staggerDelayMs(index: Int): Int {
        if (index <= 0) return 0
        val capped = if (index > StaggerMaxItems) StaggerMaxItems else index
        return capped * DurStaggerStep
    }

    @Composable
    fun rememberInteraction(): MutableInteractionSource = remember { MutableInteractionSource() }

    fun pressScale(
        interactionSource: InteractionSource,
        enabled: Boolean = true,
        pressedScale: Float = 0.97f
    ): Modifier = Modifier.lexiPressScale(interactionSource, enabled, pressedScale)

    fun clickTarget(
        interactionSource: MutableInteractionSource,
        enabled: Boolean = true,
        onClick: () -> Unit
    ): Modifier = Modifier.composed {
        Modifier.clickable(
            interactionSource = interactionSource,
            indication = LocalIndication.current,
            enabled = enabled,
            onClick = onClick
        )
    }

    @OptIn(ExperimentalFoundationApi::class)
    fun combinedClickTarget(
        interactionSource: MutableInteractionSource,
        enabled: Boolean = true,
        onLongClick: (() -> Unit)? = null,
        onClick: () -> Unit
    ): Modifier = Modifier.composed {
        Modifier.combinedClickable(
            interactionSource = interactionSource,
            indication = LocalIndication.current,
            enabled = enabled,
            onClick = onClick,
            onLongClick = onLongClick
        )
    }

    fun staggerReveal(index: Int): Modifier = Modifier.lexiStaggerReveal(index)

    @Composable
    fun animateColor(target: Color, label: String = "lexiColor"): Color {
        val reduced = rememberReducedMotion()
        val animated by animateColorAsState(
            targetValue = target,
            animationSpec = fastTween(reduced),
            label = label
        )
        return animated
    }

    @Composable
    fun animateFloat(
        target: Float,
        useSpring: Boolean = false,
        label: String = "lexiFloat"
    ): Float {
        val reduced = rememberReducedMotion()
        val animated by animateFloatAsState(
            targetValue = target,
            animationSpec = when {
                reduced -> tween(0)
                useSpring -> uiSpring()
                else -> fastTween(false)
            },
            label = label
        )
        return animated
    }

    @Composable
    fun <T> RouteContent(
        targetState: T,
        isForward: (initial: T, target: T) -> Boolean,
        content: @Composable (T) -> Unit
    ) {
        val reduced = rememberReducedMotion()
        val shiftPx = with(LocalDensity.current) { 24.dp.toPx().roundToInt() }
        AnimatedContent(
            targetState = targetState,
            transitionSpec = {
                if (reduced) {
                    fadeIn(tween(120)) togetherWith fadeOut(tween(100))
                } else if (isForward(initialState, targetState)) {
                    (fadeIn(tween(DurBase, easing = EaseOut)) +
                        slideInHorizontally(tween(DurBase, easing = EaseOut)) { shiftPx }) togetherWith
                        (fadeOut(tween(DurFast, easing = EaseOut)) +
                            slideOutHorizontally(tween(DurFast, easing = EaseOut)) { -(shiftPx / 2) })
                } else {
                    (fadeIn(tween(DurBase, easing = EaseOut)) +
                        slideInHorizontally(tween(DurBase, easing = EaseOut)) { -(shiftPx / 2) }) togetherWith
                        (fadeOut(tween(DurFast, easing = EaseOut)) +
                            slideOutHorizontally(tween(DurFast, easing = EaseOut)) { shiftPx })
                }
            },
            label = "LexiRouteTransition"
        ) { state ->
            content(state)
        }
    }

    @Composable
    fun <T> TabContent(
        targetState: T,
        tabOrder: (T) -> Int,
        content: @Composable (T) -> Unit
    ) {
        val reduced = rememberReducedMotion()
        val shiftPx = with(LocalDensity.current) { 12.dp.toPx().roundToInt() }
        AnimatedContent(
            targetState = targetState,
            transitionSpec = {
                if (reduced) {
                    fadeIn(tween(100)) togetherWith fadeOut(tween(80))
                } else {
                    val forward = tabOrder(targetState) >= tabOrder(initialState)
                    val enterShift = if (forward) shiftPx else -shiftPx
                    val exitShift = if (forward) -shiftPx else shiftPx
                    (fadeIn(tween(DurFast, easing = EaseOut)) +
                        slideInHorizontally(tween(DurFast, easing = EaseOut)) { enterShift }) togetherWith
                        (fadeOut(tween(DurMicro, easing = EaseOut)) +
                            slideOutHorizontally(tween(DurMicro, easing = EaseOut)) { exitShift })
                }
            },
            label = "LexiTabTransition"
        ) { state ->
            content(state)
        }
    }

    @Composable
    fun Expandable(
        visible: Boolean,
        modifier: Modifier = Modifier,
        content: @Composable () -> Unit
    ) {
        val reduced = rememberReducedMotion()
        AnimatedVisibility(
            visible = visible,
            modifier = modifier,
            enter = if (reduced) {
                fadeIn(tween(100))
            } else {
                expandVertically(tween(DurBase, easing = EaseOut)) +
                    fadeIn(tween(DurFast, easing = EaseOut))
            },
            exit = if (reduced) {
                fadeOut(tween(80))
            } else {
                shrinkVertically(tween(DurFast, easing = EaseOut)) +
                    fadeOut(tween(DurMicro, easing = EaseOut))
            }
        ) {
            Box {
                content()
            }
        }
    }
}

@Composable
fun rememberReducedMotion(): Boolean {
    if (LocalInspectionMode.current) return false
    val context = LocalContext.current
    return remember(context) {
        try {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f
            ) == 0f
        } catch (_: Throwable) {
            false
        }
    }
}

/**
 * Applies a subtle 0.97f tactile press scale tied to [interactionSource].
 * Place before background/border/clip modifiers so the whole surface scales together.
 */
fun Modifier.lexiPressScale(
    interactionSource: InteractionSource,
    enabled: Boolean = true,
    pressedScale: Float = 0.97f
): Modifier = composed {
    val reduced = rememberReducedMotion()
    val pressed by interactionSource.collectIsPressedAsState()
    val targetScale = if (enabled && !reduced && pressed) pressedScale else 1f
    val scale by animateFloatAsState(
        targetValue = targetScale,
        animationSpec = LexiMotion.microTween(reduced),
        label = "lexiPressScale"
    )
    this.graphicsLayer {
        scaleX = scale
        scaleY = scale
    }
}

/**
 * Staggered first-load reveal for list items (capped at 8 steps * 30ms).
 */
fun Modifier.lexiStaggerReveal(index: Int): Modifier = composed {
    val reduced = rememberReducedMotion()
    if (reduced) return@composed this
    val delayMs = LexiMotion.staggerDelayMs(index)
    var visible by remember { mutableStateOf(delayMs == 0) }
    LaunchedEffect(index) {
        if (!visible) {
            delay(delayMs.toLong())
            visible = true
        }
    }
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = LexiMotion.baseTween(reduced = false),
        label = "lexiStaggerAlpha"
    )
    val offsetY by animateFloatAsState(
        targetValue = if (visible) 0f else 10f,
        animationSpec = LexiMotion.baseTween(reduced = false),
        label = "lexiStaggerY"
    )
    this.graphicsLayer {
        this.alpha = alpha
        translationY = offsetY * density
    }
}

/**
 * Wraps modal/dialog surface content with 0.96f -> 1.0f entrance + fade.
 */
@Composable
fun LexiAnimatedDialogBox(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val reduced = rememberReducedMotion()
    var visible by remember { mutableStateOf(reduced) }
    LaunchedEffect(Unit) {
        visible = true
    }
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = if (reduced) {
            fadeIn(tween(120))
        } else {
            fadeIn(tween(LexiMotion.DurBase, easing = LexiMotion.EaseOut)) +
                scaleIn(
                    initialScale = 0.96f,
                    animationSpec = LexiMotion.uiSpring()
                ) +
                slideInVertically(
                    initialOffsetY = { it / 28 },
                    animationSpec = tween(LexiMotion.DurBase, easing = LexiMotion.EaseOut)
                )
        },
        exit = if (reduced) {
            fadeOut(tween(100))
        } else {
            fadeOut(tween(LexiMotion.DurFast, easing = LexiMotion.EaseOut)) +
                scaleOut(
                    targetScale = 0.96f,
                    animationSpec = tween(LexiMotion.DurFast, easing = LexiMotion.EaseOut)
                ) +
                slideOutVertically(
                    targetOffsetY = { it / 32 },
                    animationSpec = tween(LexiMotion.DurFast, easing = LexiMotion.EaseOut)
                )
        }
    ) {
        Box {
            content()
        }
    }
}

fun lexiExpandEnter(reduced: Boolean): EnterTransition =
    if (reduced) fadeIn(tween(100))
    else fadeIn(tween(LexiMotion.DurFast, easing = LexiMotion.EaseOut))

fun lexiCollapseExit(reduced: Boolean): ExitTransition =
    if (reduced) fadeOut(tween(80))
    else fadeOut(tween(LexiMotion.DurMicro, easing = LexiMotion.EaseOut))
