package com.lovexjy.lexinote.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Shared visual tokens for LexiNote Android, aligned with Harmony / macOS / Windows.
 */
object LexiTokens {

    object Space {
        val S0_5 = 2.dp
        val S1 = 4.dp
        val S2 = 8.dp
        val S3 = 12.dp
        val S4 = 16.dp
        val S5 = 20.dp
        val S6 = 24.dp
        val S8 = 32.dp
        val S10 = 40.dp
        val S12 = 48.dp
    }

    object Radius {
        val XS = 6.dp
        val SM = 8.dp
        val MD = 12.dp
        val LG = 16.dp
        val Card = 16.dp
        val Sheet = 20.dp
        val Pill = 999.dp
    }

    object Border {
        val Hairline = 0.5.dp
        val Strong = 1.dp
    }

    object Elev {
        val Level0 = 0.dp
        val Level1 = 2.dp
        val Level2 = 8.dp
        val Level3 = 16.dp
    }

    object Type {
        val Display = TextStyle(
            fontSize = 24.sp,
            lineHeight = 32.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.3).sp
        )
        val H1 = TextStyle(
            fontSize = 22.sp,
            lineHeight = 28.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.2).sp
        )
        val H2 = TextStyle(
            fontSize = 18.sp,
            lineHeight = 24.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.1).sp
        )
        val H3 = TextStyle(
            fontSize = 16.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold
        )
        val Body = TextStyle(
            fontSize = 15.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.Normal
        )
        val BodyMedium = TextStyle(
            fontSize = 14.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.Normal
        )
        val Caption = TextStyle(
            fontSize = 13.sp,
            lineHeight = 18.sp,
            fontWeight = FontWeight.Normal
        )
        val Micro = TextStyle(
            fontSize = 11.sp,
            lineHeight = 14.sp,
            fontWeight = FontWeight.Medium
        )
        val TnumH2 = H2.copy(fontFeatureSettings = "tnum")
        val TnumH3 = H3.copy(fontFeatureSettings = "tnum")
        val TnumBody = Body.copy(fontFeatureSettings = "tnum")
        val TnumCaption = Caption.copy(fontFeatureSettings = "tnum")
        val TnumMicro = Micro.copy(fontFeatureSettings = "tnum")
    }

    fun cardShadow(
        elevation: Dp = Elev.Level1,
        shape: Shape = RoundedCornerShape(Radius.Card),
        dark: Boolean = false
    ): Modifier {
        val spot = Color(if (dark) 0x38000000 else 0x161B1233)
        val ambient = Color(if (dark) 0x24000000 else 0x0E1B1233)
        return Modifier.shadow(
            elevation = elevation,
            shape = shape,
            spotColor = spot,
            ambientColor = ambient
        )
    }
}
